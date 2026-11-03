# C离线标定工具与ABC v1.4接口

当前适配版本：ABC v1.4r2，800×480，75 MHz，右到左计数。

灰度公式、前景极性、暖色判据、半开ROI和1/256比例与当前B流水线一致。基础配置改为当前尺寸、计时和轨迹关联默认值。

工具产生两类JSON：完整标定记录保留样本统计；ABC-1.4算法场景供控制台算法页直接载入。abc_adapter.js负责字段映射，console/vision_device.py负责整包提交和读回。

映射包括cfg_safety_roi_*、cfg_line_a/b、cfg_threshold/invert、cfg_guard_*、cfg_empty_ratio、恢复帧数、超时和轨迹关联参数。连续阈值带映射为cfg_threshold_min/max，训练空带均值用于计算cfg_mean_offset。

导入配置保持人工暂停，切到相机源并使用软件参数；清空检测区后点击“自动判遮挡”。配置版本与场景版本由现有控制台协议分配。动态去噪、三路并行、投影、合并恢复和测速配置继续沿用当前板上值。

现场采样直接使用控制台console/snapshots中的800×480原图，目标位置覆盖右、中、左。用户操作见../使用说明.md。
