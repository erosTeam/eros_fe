import 'dart:async';

import 'package:dio/dio.dart';
import 'package:eros_fe/component/quene_task/quene_task.dart';
import 'package:eros_fe/models/base/eh_models.dart';
import 'package:eros_fe/store/db/entity/gallery_task.dart';
import 'package:executor/executor.dart';
import 'package:get/get.dart';

/// 轮询周期间隔 单位秒
const int kPeriodSeconds = 1;

/// 速度显示的统计窗口（周期数），窗口越短刷新越及时
const int kMaxCount = 3;

/// 停滞检测的统计窗口（周期数）
const int kCheckMaxCount = 10;

/// 停滞检测窗口内持续无速度，再经过多少个周期才整本重试。
/// 需大于单张图片的超时 + 重试等待时间，让单图重试先生效，整本重试只做兜底。
const int kRetryThresholdTime = 30;

// 达到此次数后换源下载。图片节点连不上时在同一节点重试没有意义，所以第一次重试就换源
const int kMaxReDownloadRetries = 1;

/// 单张图片下载失败后的最大重试次数
const int kMaxImageRetries = 4;

/// 单张图片重试的基础等待时间，按 2、4、8、16 秒递增
const Duration kImageRetryBaseDelay = Duration(seconds: 2);

/// 图片节点连不上时，换源重试前的等待时间（基本不等）
const Duration kNodeErrorRetryDelay = Duration(milliseconds: 300);

/// 一轮下载结束仍有缺页时，多久后自动补下
const Duration kQuickRestartDelay = Duration(seconds: 2);

/// 每个画廊最多自动补下几次，超过后交给停滞检测，避免确实下不了的图片反复重试
const int kMaxQuickRestarts = 3;

// 等待 showKey 的最长时间，超时后不带 showKey 继续下载
const Duration kShowKeyWaitTimeout = Duration(seconds: 30);

class DownloadState {
  DownloadState();
  final RxMap<int, GalleryTask> galleryTaskMap = <int, GalleryTask>{}.obs;

  List<GalleryTask> get galleryTasks => galleryTaskMap.values.toList()
    ..sort((b, a) => (a.addTime ?? 0).compareTo(b.addTime ?? 0));

  final downloadSpeeds = <int, String>{};

  final errInfoMap = <int, String>{};

  late Executor executor;

  QueueTask queueTask = QueueTask();
  final Map<int, TaskCancelToken> taskCancelTokens = {};

  final Map<int, List<GalleryImage>> downloadMap = <int, List<GalleryImage>>{};
  final Map<int, CancelToken> cancelTokenMap = <int, CancelToken>{};
  final showKeyMap = <int, String>{};
  final showKeyCompleteMap = <int, Completer>{};

  final Map<int, Timer?> chkTimers = {};
  final Map<int, int> preComplete = {};
  final Map<int, int> curComplete = {};

  /// 每张图片当前已接收的字节数，key: "gid_ser"
  final Map<String, int> downloadCounts = {};

  /// 每个画廊累计接收的字节数（只增不减，用于计算速度）
  final Map<int, int> receivedBytes = {};

  /// 每个画廊最近若干个周期的 [receivedBytes] 采样
  final Map<int, List<int>> lastCounts = {};

  final Map<int, int> noSpeed = {};

  // 重试计数器：key: "gid_ser", value: 重试次数
  final Map<String, int> reDownloadCounts = {};

  // 每张图片最近一次解析到的换源 ID（nl），key: "gid_ser"
  final Map<String, String> imageSourceIds = {};

  // 每个画廊已自动补下的次数
  final Map<int, int> quickRestartCounts = {};

  // 画廊任务额外信息 - 新增
  final Map<int, Map<String, dynamic>> galleryTaskExtraInfo = {};
}
