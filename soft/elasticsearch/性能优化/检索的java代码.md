package com.huaying.community.service.acticle.impl;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.huaying.common.exceptions.BizException;
import com.huaying.common.helper.IObjectStorageHelper;
import com.huaying.community.client.dto.article.request.*;
import com.huaying.community.client.dto.article.response.*;
import com.huaying.community.client.dto.comment.response.CommentFirstRes;
import com.huaying.community.client.dto.comment.response.CommentRes;
import com.huaying.community.client.dto.sensitiveword.response.SensitiveWordCheckResult;
import com.huaying.community.client.enums.*;
import com.huaying.community.config.SubscriptionFeeV2ConfigProperties;
import com.huaying.community.service.user.ICommunityUserService;
import com.huaying.community.service.subscription.ISubscriptionService;
import com.huaying.community.util.TrieSensitiveWordFilter;
import com.huaying.slim.vo.PageVO;
import org.apache.commons.lang3.ObjectUtils;
import org.bson.Document;
import org.bson.types.ObjectId;
import org.elasticsearch.index.query.BoolQueryBuilder;
import org.elasticsearch.index.query.MultiMatchQueryBuilder;
import org.elasticsearch.index.query.QueryBuilders;
import org.elasticsearch.search.sort.SortBuilder;
import org.elasticsearch.search.sort.SortBuilders;
import org.elasticsearch.search.sort.SortOrder;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.elasticsearch.core.ElasticsearchRestTemplate;
import org.springframework.data.elasticsearch.core.SearchHits;
import org.springframework.data.elasticsearch.core.mapping.IndexCoordinates;
import org.springframework.data.elasticsearch.core.query.NativeSearchQuery;
import org.springframework.data.elasticsearch.core.query.NativeSearchQueryBuilder;
import org.springframework.data.elasticsearch.core.query.FetchSourceFilter;
import com.huaying.community.entity.mongo.*;
import com.huaying.community.service.acticle.IArticleLikeService;
import com.huaying.community.service.acticle.IArticleOtherService;
import com.huaying.community.service.acticle.IUserBrowseService;
import com.huaying.community.service.comment.ICommentLikeService;
import com.huaying.community.vo.ContentParseResult;
import com.huaying.community.vo.CustomTag;
import com.huaying.community.vo.ProcessResult;
import com.huaying.slim.constants.LangEnum;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.collections4.CollectionUtils;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.aggregation.Aggregation;
import org.springframework.stereotype.Service;
import com.mongodb.bulk.BulkWriteResult;
import com.mongodb.client.model.UpdateOneModel;
import com.mongodb.client.model.UpdateOptions;
import com.mongodb.client.model.WriteModel;

import java.math.BigDecimal;
import java.util.*;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.StreamSupport;

import static org.springframework.beans.BeanUtils.copyProperties;

/**
 * @author lsz
 */
@Slf4j
@Service
public class ArticleOtherServiceImpl implements IArticleOtherService {
    @Autowired
    private ICommentLikeService commentLikeService;

    @Autowired
    private MongoTemplate mongoTemplate;
    @Autowired
    private ElasticsearchRestTemplate elasticsearchRestTemplate;

    @Autowired
    private IArticleLikeService articleLikeService;
    @Autowired
    private IObjectStorageHelper objectStorageHelper;
    @Autowired
    private ICommunityUserService communityUserService;
    @Autowired
    private TrieSensitiveWordFilter trieSensitiveWordFilter;
    @Autowired
    private IUserBrowseService userBrowService;
    @Autowired
    private SubscriptionFeeV2ConfigProperties subscriptionFeeV2ConfigProperties;
    @Autowired
    private ISubscriptionService subscriptionService;

    private static final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * 分页搜索文章列表
     *
     * @param searchArticleReq 搜索请求参数
     * @return 分页结果
     */
    @Override
    public PageVO<CommunityArticleRes> searchArticleListByPage(SearchArticleReq searchArticleReq) {
        long startTime = System.currentTimeMillis();

        try {
            // 构建查询条件
            BoolQueryBuilder filter = buildFilter(searchArticleReq);
            // 构建查询对象
            NativeSearchQuery query = buildQuery(filter, searchArticleReq);
            query.setTrackTotalHits(false);

            // ES查询 - 只返回ID字段
            long esStartTime = System.currentTimeMillis();
            SearchHits<Map> searchHits = elasticsearchRestTemplate.search(
                    query, Map.class, IndexCoordinates.of("article")
            );
            log.info("ES查询耗时: {}ms", System.currentTimeMillis() - esStartTime);

            if (!searchHits.hasSearchHits()) {
                return new PageVO<>();
            }

            // 提取文章ID列表
            List<String> articleIds = searchHits.getSearchHits().stream()
                    .map(hit -> (String) hit.getContent().get("id"))
                    .filter(Objects::nonNull)
                    .collect(Collectors.toList());

            if (CollectionUtils.isEmpty(articleIds)) {
                return new PageVO<>();
            }

            // 从MongoDB批量查询完整数据
            long mongoStartTime = System.currentTimeMillis();
            List<CommunityArticleRes> list = getArticlesFromMongoDB(articleIds);
            log.info("MongoDB查询耗时: {}ms", System.currentTimeMillis() - mongoStartTime);

            // 构建响应
            long responseStartTime = System.currentTimeMillis();
            PageVO<CommunityArticleRes> pageVO = new PageVO<CommunityArticleRes>().toBuilder()
                    .page(searchArticleReq.getPage())
                    .size(searchArticleReq.getSize())
                    .records(list)
                    .build();
            log.info("响应构建耗时: {}ms", System.currentTimeMillis() - responseStartTime);

            return pageVO;

        } catch (Exception e) {
            log.error("搜索文章失败", e);
            return new PageVO<>();
        } finally {
            log.info("总耗时: {}ms", System.currentTimeMillis() - startTime);
        }
    }

    // 构建查询条件
    private BoolQueryBuilder buildFilter(SearchArticleReq searchArticleReq) {
        BoolQueryBuilder filter = QueryBuilders.boolQuery();
        filter.filter(QueryBuilders.termQuery("delFlag", "0"));
        if (StringUtils.isNotBlank(searchArticleReq.getKeyword())) {
            String keyword = searchArticleReq.getKeyword();
            MultiMatchQueryBuilder multiMatchQuery = QueryBuilders.multiMatchQuery(keyword, "title", "contentText")
                    .analyzer("ngram_analyzer")
                    .type(MultiMatchQueryBuilder.Type.PHRASE);
            filter.must(multiMatchQuery);
        }
        return filter;
    }

    // 构建ES查询对象
    private NativeSearchQuery buildQuery(BoolQueryBuilder filter, SearchArticleReq searchArticleReq) {
        SortBuilder<?> sortBuilder = SortBuilders.fieldSort("issueTime").order(SortOrder.DESC);
        Pageable pageable = PageRequest.of(searchArticleReq.getPage().intValue() - 1, searchArticleReq.getSize().intValue());

        // 只返回ID字段，大幅减少网络传输
        String[] includeFields = {"id"};
        String[] excludeFields = {};

        return new NativeSearchQueryBuilder()
                .withQuery(filter)
                .withSort(sortBuilder)
                .withPageable(pageable)
                .withSourceFilter(new FetchSourceFilter(includeFields, excludeFields))
                .build();
    }

    // 从MongoDB批量查询完整数据
    private List<CommunityArticleRes> getArticlesFromMongoDB(List<String> articleIds) {
        if (CollectionUtils.isEmpty(articleIds)) {
            return Collections.emptyList();
        }

        try {
            // 构建MongoDB查询
            Query query = new Query(Criteria.where("_id").in(articleIds));
            // 保持与ES相同的排序
            query.with(Sort.by(Sort.Direction.DESC, "issueTime"));

            // 执行查询
            List<Article> articles = mongoTemplate.find(query, Article.class);

            // 转换为响应对象
            return articles.stream()
                    .map(this::convertArticleToResponse)
                    .collect(Collectors.toList());

        } catch (Exception e) {
            log.error("从MongoDB查询文章失败", e);
            return Collections.emptyList();
        }
    }

    // 转换Article为CommunityArticleRes
    private CommunityArticleRes convertArticleToResponse(Article article) {
        CommunityArticleRes res = new CommunityArticleRes();
        // 手动设置字段，避免反射开销
        res.setId(article.getId());
        res.setTitle(article.getTitle());
        res.setContentText(article.getContentText());
        res.setIssueTime(article.getIssueTime());
        res.setReadPermission(article.getReadPermission());
        res.setOpenCommentState(article.getOpenCommentState());
        res.setMatchId(article.getMatchId());
        res.setLikeCount(article.getLikeCount());
        res.setCommentCount(article.getCommentCount());
        res.setCreateTime(article.getCreateTime());
        res.setUserId(article.getUserId());
        res.setSportType(article.getSportType());
        res.setPrice(article.getPrice());
        return res;
    }

    /**
     * 分页查询个人评论内容列表
     *
     * @param personalContentDTO 查询参数
     * @return 分页结果
     */
    @Override
    public PageVO<PersonalCommentContentVO> findPersonalCommentContentListByPage(PersonalContentDTO personalContentDTO) {
        PageVO<PersonalCommentContentVO> pageVO = new PageVO<>();
        Query query = new Query();
        Criteria criteria = Criteria.where("commentUserId").is(personalContentDTO.getUserId());
        if (CollectionUtils.isNotEmpty(personalContentDTO.getIdList())) {
            criteria.and("_id").nin(personalContentDTO.getIdList().stream().map(org.bson.types.ObjectId::new).collect(Collectors.toList()));
            personalContentDTO.setPage(personalContentDTO.getPage() - 1);
        }
        query.addCriteria(criteria);
        query.with(org.springframework.data.domain.Sort.by(org.springframework.data.domain.Sort.Direction.DESC, "createTime"));
        query.skip((personalContentDTO.getPage() - 1) * personalContentDTO.getSize()).limit(personalContentDTO.getSize().intValue());
        try {
            List<ArticleComment> articleCommentList = mongoTemplate.find(query, ArticleComment.class);
            if (CollectionUtils.isEmpty(articleCommentList)) {
                return pageVO;
            }
            Map<String, CommentLike> commentLikeMap = commentLikeService.getCommentLikeMap(personalContentDTO.getLoginUserId(), articleCommentList.stream().map(ArticleComment::getId).collect(Collectors.toList()));
            List<String> articleIds = articleCommentList.stream().map(ArticleComment::getArticleId).collect(Collectors.toList());
            Map<String, Article> articleMap = queryArticles(articleIds);
            List<String> beCommentIds = articleCommentList.stream().map(ArticleComment::getBeCommentId).collect(Collectors.toList());
            Map<String, ArticleComment> articleCommentMap = queryComments(beCommentIds);
            Map<String, ArticleFile> articleFileMap = getArticleFilesWithDetails(articleIds, true);
            List<Long> userIds = articleMap.values().stream().map(Article::getUserId).collect(Collectors.toList());
            Map<String, UserBrowse> userBrowseMap = userBrowService.getUserBrowseMap(personalContentDTO.getLoginUserId(), articleIds);
            Map<String, ArticleLike> articleLikeMap = articleLikeService.getArticleLikeMap(personalContentDTO.getLoginUserId(), articleIds);
            Map<Long, UserFan> userFollowMap = communityUserService.getUserFollowMap(personalContentDTO.getLoginUserId(), userIds);
            Map<Long, UnvoicedUser> unvoicedUserMap = communityUserService.getUnvoicedUserMap(personalContentDTO.getLoginUserId(), userIds);
            Map<Long, BlockUser> blockUserMap = communityUserService.getUserBlockMap(personalContentDTO.getLoginUserId(), userIds);
            Map<String, Subscription> subscriptionMap = subscriptionService.getSubscriptionMap(personalContentDTO.getLoginUserId(), articleIds);
            List<PersonalCommentContentVO> personalCommentContentVOList = articleCommentList.stream()
                    .map(item -> buildPersonalCommentContentVO(item, articleMap, articleCommentMap, commentLikeMap, articleFileMap, userBrowseMap, articleLikeMap, userFollowMap, unvoicedUserMap, blockUserMap, subscriptionMap, personalContentDTO.getLoginUserId()))
                    .collect(Collectors.toList());
            pageVO.setRecords(personalCommentContentVOList);
        } catch (Exception e) {
            log.error("findPersonalCommentContentListByPage error", e);
        }
        return pageVO;
    }

    /**
     * 分页查询个人点赞内容列表
     *
     * @param personalContentDTO 查询参数
     * @return 分页结果
     */
    @Override
    public PageVO<PersonalLikeContentVO> findPersonalLikeContentListByPage(PersonalContentDTO personalContentDTO) {
        if (CollectionUtils.isNotEmpty(personalContentDTO.getIdList())) {
            personalContentDTO.setPage(personalContentDTO.getPage() - 1);
        }
        int skip = (personalContentDTO.getPage().intValue() - 1) * personalContentDTO.getSize().intValue();
        List<ObjectId> idArticleLikeList = new ArrayList<>();
        List<ObjectId> idCommentLikeList = new ArrayList<>();
        if (CollectionUtils.isNotEmpty(personalContentDTO.getIdList())) {
            idArticleLikeList = personalContentDTO.getIdList().stream()
                    .filter(item -> item.contains("articleLike"))
                    .map(item -> new ObjectId(item.replace("articleLike_", "")))
                    .collect(Collectors.toList());
            idCommentLikeList = personalContentDTO.getIdList().stream()
                    .filter(item -> item.contains("commentLike"))
                    .map(item -> new ObjectId(item.replace("commentLike_", "")))
                    .collect(Collectors.toList());
        }
        List<Document> pipeline = Arrays.asList(
                new Document("$match", new Document().append("likeUserId", personalContentDTO.getUserId())
                        .append("_id", new Document("$nin", idArticleLikeList))),
                new Document("$unionWith", new Document("coll", "commentLike").append("pipeline", Arrays.asList(
                        new Document("$match", new Document().append("likeUserId", personalContentDTO.getUserId())
                                .append("_id", new Document("$nin", idCommentLikeList))
                        )))),
                new Document("$sort", new Document("createTime", -1)),
                new Document("$limit", personalContentDTO.getSize().intValue())
        );
        com.mongodb.client.AggregateIterable<Document> results = mongoTemplate.getCollection("articleLike")
                .aggregate(pipeline);
        List<Like> likeList = new ArrayList<>();
        for (Document doc : results) {
            Like likeEntity = mongoTemplate.getConverter().read(Like.class, doc);
            likeList.add(likeEntity);
        }
        List<String> articleIds = likeList.stream()
                .map(Like::getArticleId)
                .filter(StringUtils::isNotEmpty)
                .collect(Collectors.toList());
        List<String> commentIds = likeList.stream()
                .map(Like::getCommentId)
                .filter(StringUtils::isNotEmpty)
                .collect(Collectors.toList());
        Map<String, Article> articleMap = queryArticles(articleIds);
        Map<String, ArticleComment> commentMap = queryComments(commentIds);
        List<Long> userIdList = articleMap.values().stream().map(Article::getUserId).collect(Collectors.toList());
        Map<String, ArticleFile> articleFileMap = getArticleFilesWithDetails(articleIds, true);
        Map<String, UserBrowse> userBrowseMap = userBrowService.getUserBrowseMap(personalContentDTO.getUserId(), articleIds);
        Map<String, ArticleLike> articleLikeMap = articleLikeService.getArticleLikeMap(personalContentDTO.getUserId(), articleIds);
        Map<Long, UserFan> userFollowMap = communityUserService.getUserFollowMap(personalContentDTO.getUserId(), userIdList);
        Map<Long, UnvoicedUser> unvoicedUserMap = communityUserService.getUnvoicedUserMap(personalContentDTO.getUserId(), userIdList);
        Map<String, CommentLike> commentLikeMap = commentLikeService.getCommentLikeMap(personalContentDTO.getUserId(), commentIds);
        Map<Long, BlockUser> blockUserMap = communityUserService.getUserBlockMap(personalContentDTO.getUserId(), userIdList);
        Map<String, Subscription> subscriptionMap = subscriptionService.getSubscriptionMap(personalContentDTO.getUserId(), articleIds);
        List<PersonalLikeContentVO> personalLikeContentVOList = likeList.stream()
                .map(item -> buildPersonalLikeContentVO(item, articleMap, commentMap, articleFileMap, userBrowseMap, articleLikeMap, userFollowMap, unvoicedUserMap, commentLikeMap, blockUserMap, subscriptionMap, personalContentDTO.getUserId()))
                .collect(Collectors.toList());
        PageVO<PersonalLikeContentVO> pageVO = new PageVO<>();
        pageVO.setRecords(personalLikeContentVOList);
        return pageVO;
    }

    /**
     * 检查草稿文章内容、内容文本、标题是否包含敏感词，并处理
     *
     * @param draftArticleDetail 草稿文章详情
     * @return 是否需要举报
     */
    @Override
    public boolean checkSensitiveWords(DraftArticleDetail draftArticleDetail) {
        boolean report = false;
        UserStatistics userStatistics = mongoTemplate.findOne(Query.query(Criteria.where("userId").is(draftArticleDetail.getUserId())), UserStatistics.class);
        if (ObjectUtils.isEmpty(userStatistics)||Byte.valueOf("2").equals(userStatistics.getUserType())){
              return report;
        }
        // 检查并处理内容
        report |= checkAndProcessSensitiveWord(draftArticleDetail,
                draftArticleDetail.getContent(),
                draftArticleDetail::setContent);

        // 检查并处理内容文本
        report |= checkAndProcessSensitiveWord(draftArticleDetail,
                draftArticleDetail.getContentText(),
                draftArticleDetail::setContentText);

        // 检查并处理标题
        report |= checkAndProcessSensitiveWord(draftArticleDetail,
                draftArticleDetail.getTitle(),
                draftArticleDetail::setTitle);

        return report;
    }

    /**
     * 检查并处理敏感词的通用方法
     *
     * @param draftArticleDetail 草稿文章详情
     * @param text               要检查的文本
     * @param textSetter         设置处理后文本的函数
     * @return 是否需要举报
     */
    private boolean checkAndProcessSensitiveWord(DraftArticleDetail draftArticleDetail,
                                                 String text,
                                                 java.util.function.Consumer<String> textSetter) {
        if (StringUtils.isEmpty(text)) {
            return false;
        }
        SensitiveWordCheckResult sensitiveWordCheckResult = trieSensitiveWordFilter.checkAndProcessByType(
                SensitiveWordTypeEnum.PUBLISH, text, draftArticleDetail.getLang());
        if (ObjectUtils.isNotEmpty(sensitiveWordCheckResult) && sensitiveWordCheckResult.isHasSensitiveWord()) {
            // 将敏感词处理后的内容赋值给对应字段
            textSetter.accept(sensitiveWordCheckResult.getProcessedText());
            return sensitiveWordCheckResult.isNeedReport();
        }
        return false;
    }



    /**
     * 处理内容中的自定义标签（如#话题），并同步更新draftArticleDetail
     *
     * @param content            内容字符串
     * @param draftArticleDetail 草稿详情
     * @return 处理后的内容字符串
     */
    @Override
    public String processCustomTags(String content, DraftArticleDetail draftArticleDetail) {
        try {
            JsonNode contentArray = objectMapper.readTree(content);
            if (!contentArray.isArray()) {
                return content;
            }

            // 解析内容，收集标签和图片
            ContentParseResult parseResult = parseContent(contentArray, true);
            if (!parseResult.hasChanges()) {
                return content;
            }

            // 处理图片/标签/视频
            ProcessResult processResult = processTagsAndImages(parseResult, draftArticleDetail);

            // 如果draftArticleDetail中也有content，直接使用已处理好的标签映射更新它
            if (StringUtils.isNotEmpty(draftArticleDetail.getContent())) {
                JsonNode draftContentArray = objectMapper.readTree(draftArticleDetail.getContent());
                if (draftContentArray.isArray()) {
                    ArrayNode newDraftContentArray = objectMapper.createArrayNode();
                    for (JsonNode node : draftContentArray) {
                        ObjectNode newNode = (ObjectNode) node.deepCopy();
                        updateCustomTagId(newNode, processResult.getTagMappings());
                        newDraftContentArray.add(newNode);
                    }
                    draftArticleDetail.setContent(objectMapper.writeValueAsString(newDraftContentArray));
                }
            }

            // 更新内容
            return updateContent(contentArray, processResult, true);
        } catch (Exception e) {
            log.error("处理content失败: {}", content, e);
            return content;
        }
    }

    /**
     * 处理内容中的图片和视频URL为完整路径
     *
     * @param content 内容字符串
     * @return 处理后的内容字符串
     */
    @Override
    public String processContentMediaUrls(String content) {
        if (StringUtils.isEmpty(content)) {
            return content;
        }

        try {
            JsonNode contentArray = objectMapper.readTree(content);
            if (!contentArray.isArray()) {
                return content;
            }

            boolean hasChanges = false;
            ArrayNode newContentArray = objectMapper.createArrayNode();

            for (JsonNode node : contentArray) {
                ObjectNode newNode = (ObjectNode) node.deepCopy();
                if (newNode.has("insert")) {
                    JsonNode insert = newNode.get("insert");
                    // 图片URL
                    if (insert.isObject() && insert.has("customImage")) {
                        ObjectNode imageNode = (ObjectNode) insert.get("customImage");
                        if (imageNode != null && imageNode.has("src")) {
                            String imageUrl = imageNode.get("src").asText();
                            if (!imageUrl.startsWith("http")) {
                                imageNode.put("src", objectStorageHelper.getFullUrl(imageUrl));
                                hasChanges = true;
                            }
                        }
                    }
                    // 视频URL
                    if (insert.isObject() && insert.has("customVideo")) {
                        ObjectNode customVideo = (ObjectNode) insert.get("customVideo");
                        if (customVideo.has("posterUrl")) {
                            String posterUrl = customVideo.get("posterUrl").asText();
                            if (!posterUrl.startsWith("http")) {
                                customVideo.put("posterUrl", objectStorageHelper.getFullUrl(posterUrl));
                                hasChanges = true;
                            }
                        }
                        if (customVideo.has("originalFileUrl")) {
                            String originalFileUrl = customVideo.get("originalFileUrl").asText();
                            if (!originalFileUrl.startsWith("http")) {
                                customVideo.put("originalFileUrl", objectStorageHelper.getFullUrl(originalFileUrl));
                                hasChanges = true;
                            }
                        }
                    }
                }
                newContentArray.add(newNode);
            }

            return hasChanges ? objectMapper.writeValueAsString(newContentArray) : content;
        } catch (Exception e) {
            log.error("处理文章媒体URL失败: {}", content, e);
            return content;
        }
    }

    /**
     * 保存草稿文章
     *
     * @param draftArticleDTO 草稿文章DTO
     * @return 草稿ID
     */
    @Override
    public String saveDraftArticle(DraftArticleDTO draftArticleDTO) {
        // 构建草稿文章对象
        if (ArticleOpenEnum.SUBSCRIBE.equals(draftArticleDTO.getReadPermission())) {
            //校验金额
            List<BigDecimal> prices = subscriptionFeeV2ConfigProperties.getPrices();
            BigDecimal inputPrice = draftArticleDTO.getPrice();
            // 保留2位小数进行对比
            boolean priceMatch = prices.stream()
                    .anyMatch(price -> price.setScale(2, BigDecimal.ROUND_HALF_UP)
                            .compareTo(inputPrice.setScale(2, BigDecimal.ROUND_HALF_UP)) == 0);
            if (!priceMatch) {
                throw new BizException(ResultCodeEnum.PRICE_ERROR.getCode(), ResultCodeEnum.PRICE_ERROR.getMsg());
            }
            if (ObjectUtils.isEmpty(draftArticleDTO.getPrice())||draftArticleDTO.getPrice().compareTo(BigDecimal.ZERO)<=0) {
                throw new BizException(ResultCodeEnum.PRICE_ERROR.getCode(), ResultCodeEnum.PRICE_ERROR.getMsg());
            }
        }
        draftArticleDTO.setEditorType(Optional.ofNullable(draftArticleDTO.getEditorType()).orElse(EditorTypeEnum.DEFAULT));
        DraftArticle draftArticle = new DraftArticle();
        copyProperties(draftArticleDTO, draftArticle);
        // 设置创建和更新时间
        Date now = new Date();
        if (StringUtils.isEmpty(draftArticle.getId())) {
            draftArticle.setCreateTime(now);
        }
        draftArticle.setUpdateTime(now);
        draftArticle.setSportType(draftArticleDTO.getSportType());

        // 处理content中的图片和视频URL为相对路径
        if (StringUtils.isNotEmpty(draftArticleDTO.getContent())) {
            try {
                JsonNode contentArray = objectMapper.readTree(draftArticleDTO.getContent());
                if (contentArray.isArray()) {
                    ContentParseResult parseResult = parseContent(contentArray, false);
                    if (parseResult.hasChanges()) {
                        DraftArticleDetail draftArticleDetail = new DraftArticleDetail();
                        copyProperties(draftArticleDTO, draftArticleDetail);
                        ProcessResult processResult = ProcessResult.builder()
                                .imageMappings(processImages(parseResult.getImageUrls(), draftArticleDetail))
                                .videoMappings(processVideos(parseResult.getVideoInfos(), draftArticleDetail))
                                .build();
                        draftArticle.setContent(updateContent(contentArray, processResult, false));
                        draftArticleDTO.setFileList(draftArticleDetail.getFileList());
                    } else {
                        draftArticle.setContent(draftArticleDTO.getContent());
                    }
                }
            } catch (Exception e) {
                log.error("处理草稿content中的图片视频URL失败: {}", draftArticleDTO.getContent(), e);
                draftArticle.setContent(draftArticleDTO.getContent());
            }
        }

        // 设置文件列表
        if (CollectionUtils.isNotEmpty(draftArticleDTO.getFileList())) {
            List<DraftArticleFile> draftArticleFiles = draftArticleDTO.getFileList().stream().map(file -> {
                DraftArticleFile draftArticleFile = new DraftArticleFile();
                draftArticleFile.setFileUrl(objectStorageHelper.getRelatedPath(file.getFileUrl()));
                draftArticleFile.setFileType(file.getFileType());
                if (StringUtils.isNotEmpty(file.getThumbnailFileUrl())) {
                    draftArticleFile.setThumbnailFileUrl(objectStorageHelper.getRelatedPath(file.getThumbnailFileUrl()));
                }
                draftArticleFile.setWidth(file.getWidth());
                draftArticleFile.setHeight(file.getHeight());
                return draftArticleFile;
            }).collect(Collectors.toList());
            draftArticle.setDraftArticleFiles(draftArticleFiles);
        }

        // 设置文章分类
        if (draftArticleDTO.getContentCategoryDTO() != null) {
            ArticleContentCategory articleContentCategory = new ArticleContentCategory();
            articleContentCategory.setSportType(draftArticleDTO.getContentCategoryDTO().getSportType());
            articleContentCategory.setContentLabel(draftArticleDTO.getContentCategoryDTO().getContentLabel().stream()
                    .map(labelDTO -> {
                        ContentLabel label = new ContentLabel();
                        label.setLabelId(labelDTO.getLabelId());
                        label.setContentLabelCategory(labelDTO.getContentLabelCategory());
                        return label;
                    })
                    .collect(Collectors.toList()));
            draftArticle.setArticleContentCategory(articleContentCategory);
        }

        if (draftArticleDTO.getArticleLink() != null) {
            draftArticle.setArticleLink(new ArticleLink());
            copyProperties(draftArticleDTO.getArticleLink(), draftArticle.getArticleLink());
        }

        // 保存或更新草稿
        mongoTemplate.save(draftArticle);
        return draftArticle.getId();
    }

    /**
     * 解析内容，提取自定义标签、图片、视频信息
     *
     * @param contentArray 内容数组
     * @param isUpdate     是否为更新操作
     * @return 解析结果
     */
    private ContentParseResult parseContent(JsonNode contentArray, Boolean isUpdate) {
        List<CustomTag> customTags = new ArrayList<>();
        List<ContentParseResult.ImgInfo> imageUrls = new ArrayList<>();
        List<ContentParseResult.VideoInfo> videoInfos = new ArrayList<>();

        StreamSupport.stream(contentArray.spliterator(), false)
                .forEach(node -> {
                    if (isUpdate) {
                        if (node.has("attributes")
                                && node.get("attributes").has("customTag")
                                && node.get("attributes").get("customTag").has("id")
                                && node.has("insert")) {
                            String tempId = node.get("attributes").get("customTag").get("id").asText();
                            String text = node.get("insert").asText().trim();
                            if (StringUtils.isNotEmpty(text)) {
                                if (!text.startsWith("#") || text.equals("#")) {
                                    customTags.add(CustomTag.builder()
                                            .tempId(tempId)
                                            .text(text)
                                            .build());
                                }
                            }
                        }
                    }
                    if (node.has("insert")
                            && node.get("insert").isObject()
                            && node.get("insert").has("customImage")
                            && node.get("insert").get("customImage").isObject()) {
                        JsonNode imgNode = node.get("insert").get("customImage");
                        String imageUrl = imgNode.get("src").asText();
                        if (imageUrl.startsWith("http")) {
                            Integer width = imgNode.has("width") ? imgNode.get("width").asInt() : null;
                            Integer height = imgNode.has("height") ? imgNode.get("height").asInt() : null;
                            imageUrls.add(ContentParseResult.ImgInfo.builder().src(imageUrl).height(height).width(width).build());
                        }
                    }
                    if (node.has("insert") && node.get("insert").isObject() && node.get("insert").has("customVideo")) {
                        JsonNode customVideo = node.get("insert").get("customVideo");
                        if (customVideo.has("posterUrl") && customVideo.has("originalFileUrl")) {
                            videoInfos.add(ContentParseResult.VideoInfo.builder()
                                    .posterUrl(customVideo.get("posterUrl").asText())
                                    .originalFileUrl(customVideo.get("originalFileUrl").asText())
                                    .width(customVideo.has("width") ? customVideo.get("width").asInt() : null)
                                    .height(customVideo.has("height") ? customVideo.get("height").asInt() : null)
                                    .build());
                        }
                    }
                });

        return ContentParseResult.builder()
                .customTags(customTags)
                .imageUrls(imageUrls)
                .videoInfos(videoInfos)
                .build();
    }

    /**
     * 处理标签、图片、视频，返回处理结果
     *
     * @param parseResult        解析结果
     * @param draftArticleDetail 草稿详情
     * @return 处理结果
     */
    private ProcessResult processTagsAndImages(ContentParseResult parseResult, DraftArticleDetail draftArticleDetail) {
        List<ProcessResult.ImageMapping> imageMappings = processImages(parseResult.getImageUrls(), draftArticleDetail);
        List<ProcessResult.TagMapping> tagMappings = new ArrayList<>();
        if (!parseResult.getCustomTags().isEmpty()) {
            tagMappings = processCustomTags(parseResult.getCustomTags(), draftArticleDetail);
        }
        List<ProcessResult.VideoMapping> videoMappings = new ArrayList<>();
        if (!parseResult.getVideoInfos().isEmpty()) {
            videoMappings = processVideos(parseResult.getVideoInfos(), draftArticleDetail);
        }
        return ProcessResult.builder().tagMappings(tagMappings).imageMappings(imageMappings).videoMappings(videoMappings).build();
    }

    /**
     * 处理图片，生成图片映射并同步到文件列表
     *
     * @param imageUrls          图片信息列表
     * @param draftArticleDetail 草稿详情
     * @return 图片映射列表
     */
    private List<ProcessResult.ImageMapping> processImages(List<ContentParseResult.ImgInfo> imageUrls, DraftArticleDetail draftArticleDetail) {
        List<ProcessResult.ImageMapping> imageMappings = new ArrayList<>();
        if (imageUrls.isEmpty()) {
            return imageMappings;
        }
        List<File> fileList = draftArticleDetail.getFileList();
        if (fileList == null) {
            fileList = new ArrayList<>();
            draftArticleDetail.setFileList(fileList);
        }
        for (ContentParseResult.ImgInfo imageUrl : imageUrls) {
            String relativeUrl = objectStorageHelper.getRelatedPath(imageUrl.getSrc());
            imageMappings.add(ProcessResult.ImageMapping.builder()
                    .originalUrl(imageUrl.getSrc())
                    .newUrl(relativeUrl)
                    .height(imageUrl.getHeight())
                    .width(imageUrl.getWidth())
                    .build());
            File file = File.builder().fileType(FileTypeEnum.IMG).fileUrl(imageUrl.getSrc()).width(imageUrl.getWidth()).height(imageUrl.getHeight()).build();
            fileList.add(file);
        }
        return imageMappings;
    }

    /**
     * 处理自定义标签，生成标签映射并同步到文章分类
     *
     * @param customTags         标签列表
     * @param draftArticleDetail 草稿详情
     * @return 标签映射列表
     */
    private List<ProcessResult.TagMapping> processCustomTags(List<CustomTag> customTags, DraftArticleDetail draftArticleDetail) {
        if (CollectionUtils.isEmpty(customTags)) {
            return new ArrayList<>();
        }
        LangEnum lang = LangEnum.valueOf(draftArticleDetail.getLang().toUpperCase());

        List<CustomTag> tagsToProcess = customTags.stream().filter(tag -> StringUtils.isEmpty(tag.getTempId())).collect(Collectors.toList());
        List<CustomTag> existingTags = customTags.stream().filter(tag -> StringUtils.isNotEmpty(tag.getTempId())).collect(Collectors.toList());

        List<ProcessResult.TagMapping> tagMappings = new ArrayList<>();
        if (!tagsToProcess.isEmpty()) {
            Map<String, List<CustomTag>> uniqueTagsMap = tagsToProcess.stream().collect(Collectors.groupingBy(CustomTag::getText, LinkedHashMap::new, Collectors.toList()));
            List<String> uniqueTexts = new ArrayList<>(uniqueTagsMap.keySet());
            List<TopicContentCategory> existingTopics = mongoTemplate.find(
                    Query.query(Criteria.where("keyValue").regex("^(" + String.join("|", uniqueTexts.stream().map(Pattern::quote).collect(Collectors.toList())) + ")$", "i").and("lang").is(lang)),
                    TopicContentCategory.class
            );
            Map<String, TopicContentCategory> existingTopicMap = existingTopics.stream().collect(Collectors.toMap(topic -> topic.getKeyValue().toLowerCase(), topic -> topic));
            List<TopicContentCategory> newTopics = new ArrayList<>();
            Date now = new Date();
            uniqueTexts.stream().filter(text -> !existingTopicMap.containsKey(text.toLowerCase())).forEach(text -> {
                TopicContentCategory newTopic = new TopicContentCategory();
                newTopic.setKeyValue(text);
                newTopic.setCreateTime(now);
                newTopic.setUpdateTime(now);
                newTopic.setState(TopicStateEnum.OPEN);
                newTopic.setLang(lang);
                newTopic.setSportType(SportTypeEnum.FOOTBALL);
                newTopics.add(newTopic);
            });
            if (!newTopics.isEmpty()) {
                mongoTemplate.insertAll(newTopics);
            }
            Map<String, TopicContentCategory> allTopicMap = new HashMap<>(existingTopicMap);
            newTopics.forEach(topic -> allTopicMap.put(topic.getKeyValue().toLowerCase(), topic));
            tagsToProcess.forEach(tag -> {
                TopicContentCategory topic = allTopicMap.get(tag.getText().toLowerCase());
                if (topic != null && topic.getId() != null) {
                    tagMappings.add(ProcessResult.TagMapping.builder().tempId(tag.getTempId()).newId(topic.getId()).text(tag.getText()).build());
                }
            });
        }

        List<ContentLabelDTO> allContentLabels = new ArrayList<>();
        List<ContentLabelDTO> processedLabels = createContentLabels(tagMappings);
        allContentLabels.addAll(processedLabels);
        if (!existingTags.isEmpty()) {
            List<ContentLabelDTO> existingLabels = existingTags.stream().map(tag -> {
                ContentLabelDTO labelDTO = new ContentLabelDTO();
                labelDTO.setLabelId(tag.getTempId());
                labelDTO.setContentLabelCategory(ContentLabelCategoryEnum.OTHER);
                return labelDTO;
            }).collect(Collectors.toList());
            allContentLabels.addAll(existingLabels);
        }
        updateArticleContentCategory(draftArticleDetail, allContentLabels);
        return tagMappings;
    }

    /**
     * 根据标签映射生成内容标签DTO列表
     *
     * @param tagMappings 标签映射
     * @return 内容标签DTO列表
     */
    private List<ContentLabelDTO> createContentLabels(List<ProcessResult.TagMapping> tagMappings) {
        List<ContentLabelDTO> contentLabels = new ArrayList<>();
        for (ProcessResult.TagMapping mapping : tagMappings) {
            ContentLabelDTO labelDTO = new ContentLabelDTO();
            labelDTO.setLabelId(mapping.getNewId());
            labelDTO.setContentLabelCategory(ContentLabelCategoryEnum.OTHER);
            contentLabels.add(labelDTO);
        }
        return contentLabels;
    }

    /**
     * 更新文章分类中的内容标签
     *
     * @param draftArticleDetail 草稿详情
     * @param newLabels          新标签
     */
    private void updateArticleContentCategory(DraftArticleDetail draftArticleDetail, List<ContentLabelDTO> newLabels) {
        if (newLabels.isEmpty()) {
            return;
        }
        ArticleContentCategoryDTO categoryDTO = draftArticleDetail.getContentCategoryDTO();
        if (categoryDTO == null) {
            categoryDTO = new ArticleContentCategoryDTO();
            draftArticleDetail.setContentCategoryDTO(categoryDTO);
        }
        List<ContentLabelDTO> existingLabels = categoryDTO.getContentLabel();
        if (existingLabels == null) {
            existingLabels = new ArrayList<>();
            categoryDTO.setContentLabel(existingLabels);
        }
        existingLabels.addAll(newLabels);
    }

    /**
     * 根据处理结果更新内容
     *
     * @param contentArray  内容数组
     * @param processResult 处理结果
     * @param isUpdate      是否为更新操作
     * @return 更新后的内容字符串
     * @throws Exception
     */
    private String updateContent(JsonNode contentArray, ProcessResult processResult, Boolean isUpdate) throws Exception {
        ArrayNode newContentArray = objectMapper.createArrayNode();
        for (JsonNode node : contentArray) {
            ObjectNode newNode = (ObjectNode) node.deepCopy();
            if (isUpdate) {
                updateCustomTagId(newNode, processResult.getTagMappings());
            }
            updateImageUrl(newNode, processResult.getImageMappings());
            updateVideoUrls(newNode, processResult.getVideoMappings());
            newContentArray.add(newNode);
        }
        return objectMapper.writeValueAsString(newContentArray);
    }

    /**
     * 更新自定义标签ID
     *
     * @param node        节点
     * @param tagMappings 标签映射
     */
    private void updateCustomTagId(ObjectNode node, List<ProcessResult.TagMapping> tagMappings) {
        if (node.has("attributes")) {
            ObjectNode attributes = (ObjectNode) node.get("attributes");
            if (attributes.has("customTag")) {
                ObjectNode customTag = (ObjectNode) attributes.get("customTag");
                if (customTag != null && customTag.has("id")) {
                    // 获取当前节点的insert内容（标签文本）
                    String insertText = node.has("insert") ? node.get("insert").asText() : "";
                    if (StringUtils.isNotEmpty(insertText)) {
                        // 根据文本内容匹配标签映射
                        tagMappings.stream()
                                .filter(mapping -> insertText.equals(mapping.getText()))
                                .findFirst()
                                .ifPresent(mapping -> customTag.put("id", mapping.getNewId()));
                    }
                }
            }
        }
    }

    /**
     * 更新图片URL
     *
     * @param node          节点
     * @param imageMappings 图片映射
     */
    private void updateImageUrl(ObjectNode node, List<ProcessResult.ImageMapping> imageMappings) {
        if (node.has("insert")) {
            JsonNode insert = node.get("insert");
            if (insert.isObject() && insert.has("customImage") && insert.get("customImage").isObject()) {
                JsonNode imageNode = insert.get("customImage");
                String oldUrl = imageNode.get("src").asText();
                imageMappings.stream().filter(mapping -> mapping.getOriginalUrl().equals(oldUrl)).findFirst().ifPresent(mapping -> {
                    ((ObjectNode) imageNode).put("src", mapping.getNewUrl());
                    if (mapping.getWidth() != null) {
                        ((ObjectNode) imageNode).put("width", mapping.getWidth());
                    }
                    if (mapping.getHeight() != null) {
                        ((ObjectNode) imageNode).put("height", mapping.getHeight());
                    }
                });
            }
        }
    }

    /**
     * 处理视频，生成视频映射并同步到文件列表
     *
     * @param videoInfos         视频信息列表
     * @param draftArticleDetail 草稿详情
     * @return 视频映射列表
     */
    private List<ProcessResult.VideoMapping> processVideos(List<ContentParseResult.VideoInfo> videoInfos, DraftArticleDetail draftArticleDetail) {
        List<ProcessResult.VideoMapping> videoMappings = new ArrayList<>();
        if (videoInfos.isEmpty()) {
            return videoMappings;
        }
        List<File> fileList = draftArticleDetail.getFileList();
        if (fileList == null) {
            fileList = new ArrayList<>();
            draftArticleDetail.setFileList(fileList);
        }
        for (ContentParseResult.VideoInfo videoInfo : videoInfos) {
            String newPosterUrl = objectStorageHelper.getRelatedPath(videoInfo.getPosterUrl());
            String newFileUrl = objectStorageHelper.getRelatedPath(videoInfo.getOriginalFileUrl());
            videoMappings.add(ProcessResult.VideoMapping.builder()
                    .originalPosterUrl(videoInfo.getPosterUrl())
                    .newPosterUrl(newPosterUrl)
                    .originalFileUrl(videoInfo.getOriginalFileUrl())
                    .newFileUrl(newFileUrl)
                    .width(videoInfo.getWidth())
                    .height(videoInfo.getHeight())
                    .build());
            fileList.add(File.builder().fileType(FileTypeEnum.VIDEO).fileUrl(videoInfo.getOriginalFileUrl()).thumbnailFileUrl(videoInfo.getPosterUrl()).height(videoInfo.getHeight()).width(videoInfo.getWidth()).build());
        }
        return videoMappings;
    }

    /**
     * 更新视频URL
     *
     * @param node          节点
     * @param videoMappings 视频映射
     */
    private void updateVideoUrls(ObjectNode node, List<ProcessResult.VideoMapping> videoMappings) {
        if (node.has("insert")) {
            JsonNode insert = node.get("insert");
            if (insert.isObject() && insert.has("customVideo")) {
                ObjectNode customVideo = (ObjectNode) insert.get("customVideo");
                String posterUrl = customVideo.get("posterUrl").asText();
                String originalFileUrl = customVideo.get("originalFileUrl").asText();
                videoMappings.stream().filter(mapping -> mapping.getOriginalPosterUrl().equals(posterUrl) && mapping.getOriginalFileUrl().equals(originalFileUrl)).findFirst().ifPresent(mapping -> {
                    customVideo.put("posterUrl", mapping.getNewPosterUrl());
                    customVideo.put("originalFileUrl", mapping.getNewFileUrl());
                    if (mapping.getWidth() != null) {
                        customVideo.put("width", mapping.getWidth());
                    }
                    if (mapping.getHeight() != null) {
                        customVideo.put("height", mapping.getHeight());
                    }
                });
            }
        }
    }

    /**
     * 查询文章信息
     *
     * @param articleIds 文章ID列表
     * @return 文章Map
     */
    private Map<String, Article> queryArticles(List<String> articleIds) {
        if (CollectionUtils.isEmpty(articleIds)) {
            return Collections.emptyMap();
        }
        List<Article> articleList = mongoTemplate.find(new Query(Criteria.where("_id").in(articleIds)), Article.class);
        return articleList.stream().collect(Collectors.toMap(Article::getId, article -> article));
    }

    /**
     * 查询评论信息
     *
     * @param commentIds 评论ID列表
     * @return 评论Map
     */
    private Map<String, ArticleComment> queryComments(List<String> commentIds) {
        if (CollectionUtils.isEmpty(commentIds)) {
            return Collections.emptyMap();
        }
        List<ArticleComment> commentList = mongoTemplate.find(new Query(Criteria.where("_id").in(commentIds)), ArticleComment.class);
        return commentList.stream().collect(Collectors.toMap(ArticleComment::getId, comment -> comment));
    }

    /**
     * 查询文章文件信息并处理URL
     *
     * @param articleId        文章ID列表
     * @param needThumbnailCut 是否需要缩略图裁剪
     * @return 文章文件Map
     */
    @Override
    public Map<String, ArticleFile> getArticleFilesWithDetails(List<String> articleId, boolean needThumbnailCut) {
        Query query = new Query(Criteria.where("articleId").in(articleId));
        List<ArticleFile> articleFiles = mongoTemplate.find(query, ArticleFile.class);
        for (ArticleFile af : articleFiles) {
            af.getArticleFiles().forEach(file -> {
                String originalUrl = file.getFileUrl();
                if (originalUrl != null && !originalUrl.isEmpty()) {
                    file.setFileUrl(objectStorageHelper.getFullUrl(originalUrl));
                    if (FileTypeEnum.VIDEO.equals(file.getFileType())) {
                        if (StringUtils.isNotBlank(file.getThumbnailFileUrl())) {
                            file.setThumbnailFileUrl(objectStorageHelper.getFullUrl(file.getThumbnailFileUrl(), needThumbnailCut));
                        }
                    } else {
                        if (StringUtils.isBlank(file.getThumbnailFileUrl())) {
                            file.setThumbnailFileUrl(objectStorageHelper.getFullUrl(originalUrl, needThumbnailCut));
                        }
                    }
                }
            });
        }
        return articleFiles.stream().collect(Collectors.toMap(ArticleFile::getArticleId, af -> af, (existing, replacement) -> existing));
    }

    /**
     * 构建个人评论内容VO
     *
     * @param item              评论
     * @param articleMap        文章Map
     * @param articleCommentMap 评论Map
     * @param commentLikeMap    评论点赞Map
     * @param articleFileMap    文章文件Map
     * @param userBrowseMap     用户浏览Map
     * @param articleLikeMap    文章点赞Map
     * @param userFollowMap     用户关注Map
     * @param unvoicedUserMap   用户静音Map
     * @param blockUserMap      用户拉黑Map
     * @param subscriptionMap   订阅Map
     * @param userId            用户ID
     * @return 个人评论内容VO
     */
    private PersonalCommentContentVO buildPersonalCommentContentVO(ArticleComment item,
                                                                   Map<String, Article> articleMap,
                                                                   Map<String, ArticleComment> articleCommentMap,
                                                                   Map<String, CommentLike> commentLikeMap,
                                                                   Map<String, ArticleFile> articleFileMap,
                                                                   Map<String, UserBrowse> userBrowseMap,
                                                                   Map<String, ArticleLike> articleLikeMap,
                                                                   Map<Long, UserFan> userFollowMap,
                                                                   Map<Long, UnvoicedUser> unvoicedUserMap,
                                                                   Map<Long, BlockUser> blockUserMap,
                                                                   Map<String, Subscription> subscriptionMap,
                                                                   Long userId) {
        PersonalCommentContentVO personalCommentContentVO = new PersonalCommentContentVO();
        personalCommentContentVO.setId(item.getId());
        Article article = articleMap.get(item.getArticleId());
        List<Long> userIdList = new ArrayList<>();
        if (article != null) {
            CommunityArticleRes communityArticleRes = new CommunityArticleRes();
            copyProperties(article, communityArticleRes);
            communityArticleRes = getCommunityArticleRes(communityArticleRes, articleFileMap, userBrowseMap, articleLikeMap, userFollowMap, unvoicedUserMap, blockUserMap, subscriptionMap, userId);
            personalCommentContentVO.setPost(communityArticleRes);
            userIdList.add(article.getUserId());
        }
        if (StringUtils.isEmpty(item.getFirstCommentId())) {
            if (article != null) {
                personalCommentContentVO.setMatchId(article.getMatchId());
                userIdList.add(article.getUserId());
                PersonalRelatedCommentContentVO personalRelatedCommentContentVO = new PersonalRelatedCommentContentVO();
                personalRelatedCommentContentVO.setCommunityArticleRes(personalCommentContentVO.getPost());
                personalCommentContentVO.setPersonalRelatedCommentContentVO(personalRelatedCommentContentVO);
            }
            PersonalCurrentCommentContentVO personalCurrentCommentContentVO = new PersonalCurrentCommentContentVO();
            CommentFirstRes commentFirstRes = new CommentFirstRes();
            copyProperties(item, commentFirstRes);
            commentFirstRes.setLike(commentLikeMap.get(item.getId()) != null);
            userIdList.add(item.getCommentUserId());
            personalCurrentCommentContentVO.setCommentFirstRes(commentFirstRes);
            personalCommentContentVO.setPersonalCurrentCommentContentVO(personalCurrentCommentContentVO);
        } else {
            PersonalRelatedCommentContentVO personalRelatedCommentContentVO = new PersonalRelatedCommentContentVO();
            userIdList.add(item.getCommentUserId());
            userIdList.add(item.getBeCommentUserId());
            if (item.getFirstCommentId().equals(item.getBeCommentId())) {
                ArticleComment articleComment = articleCommentMap.get(item.getBeCommentId());
                if (articleComment != null) {
                    CommentFirstRes commentFirstRes = new CommentFirstRes();
                    copyProperties(articleComment, commentFirstRes);
                    commentFirstRes.setLike(commentLikeMap.get(item.getId()) != null);
                    personalRelatedCommentContentVO.setCommentFirstRes(commentFirstRes);
                }
            } else {
                ArticleComment articleComment = articleCommentMap.get(item.getBeCommentId());
                if (articleComment != null) {
                    CommentRes commentRes = new CommentRes();
                    copyProperties(articleComment, commentRes);
                    commentRes.setLike(commentLikeMap.get(item.getId()) != null);
                    personalRelatedCommentContentVO.setCommentRes(commentRes);
                }
            }
            personalCommentContentVO.setPersonalRelatedCommentContentVO(personalRelatedCommentContentVO);
            PersonalCurrentCommentContentVO personalCurrentCommentContentVO = new PersonalCurrentCommentContentVO();
            CommentRes commentRes = new CommentRes();
            copyProperties(item, commentRes);
            personalCurrentCommentContentVO.setCommentRes(commentRes);
            personalCommentContentVO.setPersonalCurrentCommentContentVO(personalCurrentCommentContentVO);
        }
        personalCommentContentVO.setUserIdList(userIdList.stream().distinct().collect(Collectors.toList()));
        return personalCommentContentVO;
    }

    /**
     * 构建个人点赞内容VO
     *
     * @param like            点赞
     * @param articleMap      文章Map
     * @param commentMap      评论Map
     * @param articleFileMap  文章文件Map
     * @param userBrowseMap   用户浏览Map
     * @param articleLikeMap  文章点赞Map
     * @param userFollowMap   用户关注Map
     * @param unvoicedUserMap 用户静音Map
     * @param commentLikeMap  评论点赞Map
     * @param blockUserMap    用户拉黑Map
     * @param subscriptionMap 订阅Map
     * @param userId          用户ID
     * @return 个人点赞内容VO
     */
    private PersonalLikeContentVO buildPersonalLikeContentVO(Like like,
                                                             Map<String, Article> articleMap,
                                                             Map<String, ArticleComment> commentMap,
                                                             Map<String, ArticleFile> articleFileMap,
                                                             Map<String, UserBrowse> userBrowseMap,
                                                             Map<String, ArticleLike> articleLikeMap,
                                                             Map<Long, UserFan> userFollowMap,
                                                             Map<Long, UnvoicedUser> unvoicedUserMap,
                                                             Map<String, CommentLike> commentLikeMap,
                                                             Map<Long, BlockUser> blockUserMap,
                                                             Map<String, Subscription> subscriptionMap,
                                                             Long userId) {
        PersonalLikeContentVO personalLikeContentVO = new PersonalLikeContentVO();
        String id = like.getId();
        List<Long> userIdList = new ArrayList<>();
        if (StringUtils.isNotEmpty(like.getArticleId())) {
            Article article = articleMap.get(like.getArticleId());
            if (article != null) {
                userIdList.add(article.getUserId());
                personalLikeContentVO.setMatchId(article.getMatchId());
                CommunityArticleRes communityArticleRes = new CommunityArticleRes();
                copyProperties(article, communityArticleRes);
                personalLikeContentVO.setCommunityArticleRes(getCommunityArticleRes(communityArticleRes, articleFileMap, userBrowseMap, articleLikeMap, userFollowMap, unvoicedUserMap, blockUserMap, subscriptionMap, userId));
            }
            personalLikeContentVO.setId("articleLike_" + id);
        } else {
            ArticleComment comment = commentMap.get(like.getCommentId());
            if (comment != null) {
                userIdList.add(comment.getCommentUserId());
                if (StringUtils.isNotEmpty(comment.getFirstCommentId())) {
                    CommentRes commentRes = new CommentRes();
                    copyProperties(comment, commentRes);
                    commentRes.setLike(commentLikeMap.get(comment.getId()) != null);
                    personalLikeContentVO.setCommentRes(commentRes);
                    userIdList.add(comment.getBeCommentUserId());
                } else {
                    CommentFirstRes commentFirstRes = new CommentFirstRes();
                    copyProperties(comment, commentFirstRes);
                    commentFirstRes.setLike(commentLikeMap.get(comment.getId()) != null);
                    personalLikeContentVO.setCommentFirstRes(commentFirstRes);
                }
            }
            personalLikeContentVO.setId("commentLike_" + id);
        }
        personalLikeContentVO.setUserIdList(userIdList.stream().distinct().collect(Collectors.toList()));
        return personalLikeContentVO;
    }

    /**
     * 构建社区文章响应对象，处理权限、文件、媒体URL等
     *
     * @param communityArticleRes 文章响应对象
     * @param articleFileMap      文章文件Map
     * @param userBrowseMap       用户浏览Map
     * @param articleLikeMap      文章点赞Map
     * @param userFollowMap       用户关注Map
     * @param unvoicedUserMap     用户静音Map
     * @param userBlockMap        用户拉黑Map
     * @param subscriptionMap     订阅Map
     * @param userId              用户ID
     * @return 处理后的文章响应对象
     */
    private CommunityArticleRes getCommunityArticleRes(CommunityArticleRes communityArticleRes,
                                                       Map<String, ArticleFile> articleFileMap,
                                                       Map<String, UserBrowse> userBrowseMap,
                                                       Map<String, ArticleLike> articleLikeMap,
                                                       Map<Long, UserFan> userFollowMap,
                                                       Map<Long, UnvoicedUser> unvoicedUserMap,
                                                       Map<Long, BlockUser> userBlockMap,
                                                       Map<String, Subscription> subscriptionMap,
                                                       Long userId) {
        if (userId == null) {
            communityArticleRes.setIsFollow(false);
            communityArticleRes.setIsUnvoiced(false);
            communityArticleRes.setIsBlock(false);
            communityArticleRes.setIsSubscription(false);
            communityArticleRes.setIsRead(false);
        } else {
            UserBrowse userBrowse = userBrowseMap.get(communityArticleRes.getId());
            communityArticleRes.setIsRead(Objects.nonNull(userBrowse));
            ArticleLike articleLike = articleLikeMap.get(communityArticleRes.getId());
            communityArticleRes.setLike(Objects.nonNull(articleLike));
            if (communityArticleRes.getUserId().equals(userId)) {
                communityArticleRes.setIsSubscription(true);
                communityArticleRes.setIsFollow(false);
                communityArticleRes.setIsUnvoiced(false);
                communityArticleRes.setIsBlock(false);
            } else {
                Subscription subscription = subscriptionMap.get(communityArticleRes.getId());
                communityArticleRes.setIsSubscription(Objects.nonNull(subscription));
                UserFan userFollow = userFollowMap.get(communityArticleRes.getUserId());
                communityArticleRes.setIsFollow(Objects.nonNull(userFollow));
                UnvoicedUser unvoicedUser = unvoicedUserMap.get(communityArticleRes.getUserId());
                communityArticleRes.setIsUnvoiced(Objects.nonNull(unvoicedUser));
                BlockUser userBlock = userBlockMap.get(communityArticleRes.getUserId());
                communityArticleRes.setIsBlock(Objects.nonNull(userBlock));
            }
        }
        if (ArticleOpenEnum.SUBSCRIBE.equals(communityArticleRes.getReadPermission()) && !communityArticleRes.getIsSubscription()) {
            communityArticleRes.setContent(null);
            communityArticleRes.setContentText(null);
        } else {
            ArticleFile articleFile = articleFileMap.get(communityArticleRes.getId());
            if (Objects.nonNull(articleFile)) {
                List<File> files = articleFile.getArticleFiles().stream().map(CommunityArticleFile::toFile).collect(Collectors.toList());
                communityArticleRes.setFileList(files);
            }
        }
        communityArticleRes.setContent(processContentMediaUrls(communityArticleRes.getContent()));
        return communityArticleRes;
    }

    @Override
    public void statisticsThirtyArticleCount() {
        Date thirtyDaysAgo = new Date(System.currentTimeMillis() - 30 * 24 * 60 * 60 * 1000L);
        List<org.bson.Document> results = mongoTemplate.aggregate(
                Aggregation.newAggregation(
                        Aggregation.match(Criteria.where("issueTime").gte(thirtyDaysAgo).and("delFlag").is("0")),
                        Aggregation.group("userId")
                                .count().as("thirtyArticleCount")
                ),
                "article",
                org.bson.Document.class
        ).getMappedResults();

        List<WriteModel<org.bson.Document>> bulkOperations = results.stream()
                .map(doc -> new UpdateOneModel<org.bson.Document>(
                        new org.bson.Document("userId", doc.get("_id")),
                        new org.bson.Document("$set", new org.bson.Document("thirtyArticleCount", doc.get("thirtyArticleCount"))),
                        new UpdateOptions().upsert(false)
                ))
                .collect(Collectors.toList());

        if (!bulkOperations.isEmpty()) {
            BulkWriteResult result = mongoTemplate.getDb()
                    .getCollection("userStatistics")
                    .bulkWrite(bulkOperations);

            log.info("Bulk update completed: {} documents modified", result.getModifiedCount());
        }
    }
}
