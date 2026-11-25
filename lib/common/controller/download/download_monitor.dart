import 'dart:async';
import 'dart:math';

import 'package:eros_fe/common/controller/download_state.dart';
import 'package:eros_fe/index.dart';

class DownloadMonitor {
  DownloadMonitor(this.dState);
  final DownloadState dState;

  /// 初始化下载任务计时器
  void initDownloadStateChkTimer(int gid, {Function? onTimerCallback}) {
    // 每隔[kPeriodSeconds]时间， 执行一次
    dState.chkTimers[gid] = Timer.periodic(
      const Duration(seconds: kPeriodSeconds),
      (Timer timer) {
        if (onTimerCallback != null) {
          Function.apply(onTimerCallback, [gid, timer]);
          return;
        }

        // 此处为默认实现，当没有提供回调时使用
        final task = dState.galleryTaskMap[gid];
        if (task != null && task.fileCount == task.completCount) {
          cancelDownloadStateChkTimer(gid: gid);
          return;
        }

        if (dState.galleryTaskMap[gid]?.status == 2) {
          // 运行状态
          // 分别调用两个拆分后的方法
          updateDownloadSpeed(
            gid,
            maxCount: kMaxCount,
            periodSeconds: kPeriodSeconds,
          );

          checkDownloadStall(
            gid,
            checkMaxCount: kCheckMaxCount,
            periodSeconds: kPeriodSeconds,
          );
        }
      },
    );
  }

  /// 取消下载任务定时器
  void cancelDownloadStateChkTimer({int? gid}) {
    if (gid != null) {
      dState.downloadSpeeds.remove(gid);
      dState.noSpeed.remove(gid);
      dState.chkTimers[gid]?.cancel();
    } else {
      for (final Timer? timer in dState.chkTimers.values) {
        timer?.cancel();
      }
      dState.downloadSpeeds.clear();
      dState.noSpeed.clear();
    }
  }

  /// 计算并更新下载速度显示
  void updateDownloadSpeed(int gid, {int maxCount = 3, int periodSeconds = 1}) {
    // 使用累计接收字节数（只增不减），单张图片重试不会让总量回退
    final int totCurCount = dState.receivedBytes[gid] ?? 0;

    // 记录历史数据，只保留计算所需的最近若干个采样
    final List<int> lastCounts =
        dState.lastCounts.putIfAbsent(gid, () => [totCurCount]);
    lastCounts.add(totCurCount);
    final int keep = max(maxCount, kCheckMaxCount) + 1;
    if (lastCounts.length > keep) {
      lastCounts.removeRange(0, lastCounts.length - keep);
    }

    final speedShow = _speedOfWindow(lastCounts, maxCount, periodSeconds);

    logger.t('speedShow:${renderSize(speedShow)}');

    // 更新UI显示
    dState.downloadSpeeds[gid] = renderSize(speedShow);
  }

  /// 计算最近 [window] 个周期内的平均速度（字节/秒）
  int _speedOfWindow(List<int> samples, int window, int periodSeconds) {
    if (samples.length < 2) {
      return 0;
    }
    final int start = max(0, samples.length - 1 - window);
    final int periods = samples.length - 1 - start;
    final int delta = max(samples.last - samples[start], 0);
    return (delta / (periods * periodSeconds)).round();
  }

  /// 检查下载是否停滞并触发回调（需在 [updateDownloadSpeed] 之后调用）
  void checkDownloadStall(
    int gid, {
    int checkMaxCount = 10,
    int periodSeconds = 1,
    Function? onRetryNeededCallback,
  }) {
    final List<int> lastCounts = dState.lastCounts[gid] ?? [0];

    // 计算用于检查停滞的速度（使用较长时间窗口，更稳定）
    final speedCheck =
        _speedOfWindow(lastCounts, checkMaxCount, periodSeconds);

    logger.t('speedCheck:${renderSize(speedCheck)}');

    // 处理停滞情况
    if (speedCheck == 0) {
      // 增加无速度计数
      if (dState.noSpeed[gid] != null) {
        dState.noSpeed[gid] = dState.noSpeed[gid]! + 1;
      } else {
        dState.noSpeed[gid] = 1;
      }

      // 达到重试阈值时执行重试
      if ((dState.noSpeed[gid] ?? 0) > kRetryThresholdTime) {
        logger.d('monitor 检测到下载停滞，正在重试 gid:$gid, 时间:${DateTime.now()}');

        // 如果提供了回调则调用
        if (onRetryNeededCallback != null) {
          Function.apply(onRetryNeededCallback, [gid]);
        }

        // 重置计数器，避免重复触发重试
        dState.noSpeed[gid] = 0;
      }
    } else {
      // 有速度时重置无速度计数
      dState.noSpeed[gid] = 0;
    }
  }
}
