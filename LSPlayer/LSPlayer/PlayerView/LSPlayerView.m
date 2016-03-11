

//
//  LSPlayerView.m
//  LSPlayer
//
//  Created by ls on 16/3/8.
//  Copyright © 2016年 song. All rights reserved.
//

#import "LSPlayerMaskView.h"
#import "LSPlayerView.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <MediaPlayer/MediaPlayer.h>

#define kLSPlayerViewContentOffset @"contentOffset"

#define CellImageViewHeight 200

@interface LSPlayerView () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) NSTimer* timer;

@property (nonatomic, strong) AVPlayer* player;

@property (nonatomic, strong) AVPlayerLayer* playerLayer;

@property (nonatomic, strong) AVPlayerItem* playerItem;

//当前播放时间
@property (nonatomic, assign) CGFloat currentTime;

//所处位置
@property (nonatomic, assign) LSPLayerViewLocationType locationType;

//是否全屏
@property (nonatomic, assign, getter=isFullScreen) BOOL fullScreen;

//是否上锁
@property (nonatomic, assign) BOOL isLocked;

//@property (nonatomic, assign) BOOL isNewworkBad;
//@property (nonatomic, assign) BOOL isAlreadyPlayed; //判断在网络不好的情况下是否播放过还是就压根没有播放成功
//@property (nonatomic, assign) BOOL isSendConnect; //断网后会自动发起连接

//是否隐藏maskView
@property (nonatomic, assign, getter=isHideMaskView) BOOL hideMaskView;

//播放是否失败决定是否显示重试
@property (nonatomic, assign) BOOL isFailed;

//是否播放完成
@property (nonatomic, assign, getter=isCompletedPlay) BOOL completedPlay;

//蒙板
@property (nonatomic, weak) LSPlayerMaskView* playerMaskView;

//重新重试按钮
@property (weak, nonatomic) IBOutlet UIButton* retryButton;

//重试按钮提示语
@property (weak, nonatomic) IBOutlet UILabel* retryTipLabel;

//是否隐藏maskView
@property (nonatomic, assign) BOOL isHideMaskView;

//当前设备方向
@property (nonatomic, assign) UIInterfaceOrientation currentOrientation;

//竖屏frame
@property (nonatomic, assign) CGRect portraitFrame;

//拖拽手势
@property (nonatomic, strong) UIPanGestureRecognizer* panGesture;

//标志是否监听过contentOffset
@property (nonatomic, assign, getter=isMonitoring) BOOL monitoring;

//捏合手势
@property (nonatomic, strong) UIPinchGestureRecognizer* pinchGesture;

@end

@implementation LSPlayerView

static LSPlayerView* playerView = nil;
+ (instancetype)playerView
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        playerView = [[[NSBundle mainBundle] loadNibNamed:@"LSPlayerView" owner:nil options:nil] lastObject];
    });
    return playerView;
}
#pragma mark - 初始化playerView事件
- (void)initPlayerViewEvents
{

    self.image = [self imageWithOriginalImage:[UIImage imageNamed:@"VideoCoverDefault"]];

    UIPinchGestureRecognizer* pinGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePincgGesture:)];
    [self addGestureRecognizer:pinGesture];
    pinGesture.enabled = NO;
    self.pinchGesture = pinGesture;

    UIPanGestureRecognizer* panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    [self addGestureRecognizer:panGesture];
    panGesture.delegate = self;
    self.panGesture = panGesture;

    [self.retryButton addTarget:self action:@selector(retryButtonClick:) forControlEvents:UIControlEventTouchUpInside];
    UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapClick)];
    [self addGestureRecognizer:tap];

    self.locationType = LSPLayerViewLocationTypeMiddle; //需放在添加手势后面 因为手势禁用根据所处位置在set方法里

    //监听失去焦点通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willResignActive) name:UIApplicationWillResignActiveNotification object:nil];

    //监听进入后台通知

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (void)awakeFromNib
{

    [self listeningRotating];
    [self initPlayerViewEvents];
}
#pragma mark - 捏合手势

- (void)handlePincgGesture:(UIPinchGestureRecognizer*)gesture
{

    if (gesture.state == UIGestureRecognizerStateEnded)
        return;
    if (gesture.state == UIGestureRecognizerStateCancelled)
        return;
    if (gesture.state == UIGestureRecognizerStateFailed)
        return;
    self.layer.transform = CATransform3DScale(self.layer.transform, gesture.scale, gesture.scale, 1);
    //    self.transform=CGAffineTransformScale(self.transform, gesture.scale, gesture.scale);
    CGSize size = [UIScreen mainScreen].bounds.size;
    if (self.frame.size.width >= size.width) {
        self.transform = CGAffineTransformIdentity;
        gesture.enabled = NO;
        [UIView animateWithDuration:1 delay:0 usingSpringWithDamping:10 initialSpringVelocity:10 options:UIViewAnimationOptionCurveEaseOut animations:^{

            self.frame = CGRectMake(0, self.frame.origin.y, size.width, CellImageViewHeight);
            [self setNeedsLayout];
            [self layoutIfNeeded];
        }
            completion:^(BOOL finished) {
                gesture.enabled = YES;

            }];
        [UIView animateWithDuration:0.5 animations:^{
        }];
    }
    [gesture setScale:1];
}
#pragma mark - 拖拽手势处理
- (void)handlePanGesture:(UIPanGestureRecognizer*)gesture
{

    if (self.locationType == LSPLayerViewLocationTypeTop) {
        //从上开始滑动
        [self handlePanTopGesture:gesture];
    }
    else {
        //从下开始滑动
        [self handlePanBottomGesture:gesture];
    }
}
- (void)handlePanBottomGesture:(UIPanGestureRecognizer*)gesture
{
    CGPoint point = [gesture locationInView:[UIApplication sharedApplication].keyWindow];
    static CGPoint center;
    static CGPoint lastPoint;
    switch (gesture.state) {

    case UIGestureRecognizerStateBegan:
        lastPoint = point;
        center = self.center;

        break;
    case UIGestureRecognizerStateChanged: {
        NSLog(@"size==%@   拖拽位置   %@", NSStringFromCGPoint(self.center), NSStringFromCGPoint(point));
        self.center = CGPointMake(center.x + point.x - lastPoint.x, center.y + point.y - lastPoint.y);
        //            self.transform=CGAffineTransformMakeTranslation(point.x, point.y);
        //            [gesture setTranslation:CGPointZero inView:gesture.view];
        break;
    }
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:

        break;
    default:
        break;
    }
}
- (void)handlePanTopGesture:(UIPanGestureRecognizer*)gesture
{
    CGPoint point = [gesture translationInView:gesture.view];
    switch (gesture.state) {
    case UIGestureRecognizerStatePossible:
    case UIGestureRecognizerStateBegan:
    case UIGestureRecognizerStateChanged:
        self.transform = CGAffineTransformTranslate(self.transform, 0, point.y);
        [gesture setTranslation:CGPointZero inView:gesture.view];
        break;
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
        //是从顶部拖动
        if (self.locationType == LSPLayerViewLocationTypeTop) {
            if (self.frame.origin.y + self.frame.size.height / 2 > [UIScreen mainScreen].bounds.size.height / 2) {
                [UIView animateWithDuration:0.5 animations:^{
                    self.locationType = LSPLayerViewLocationTypeBottom;
                    self.transform = CGAffineTransformIdentity;
                    [self updataPlayerViewBottomFrame];

                }];
            }
            else {
                [UIView animateWithDuration:0.5 animations:^{
                    self.transform = CGAffineTransformIdentity;
                }];
            }
        }
        break;
    }
}
#pragma mark - playerView单击手势
- (void)tapClick
{

    if (self.isFullScreen) {
        [self topAndMiddleTapClick];
        return;
    }
    switch (self.locationType) {
    case LSPLayerViewLocationTypeMiddle: {
        [self topAndMiddleTapClick];
        break;
    }
    case LSPLayerViewLocationTypeTop: {
        [self topAndMiddleTapClick];
        break;
    }
    case LSPLayerViewLocationTypeBottom: {
        [self bottomTapClick];
        break;
    }
    case LSPLayerViewLocationTypeDragging: {

        break;
    }
    }
}
#pragma mark - BottomTapClick
- (void)bottomTapClick
{
    [self playOrPause:self.playerMaskView.playButton];
}

#pragma mark - TopAndMiddleTapClick
- (void)topAndMiddleTapClick
{
    if (self.isHideMaskView) {
        [self startShowMaskView];
    }
    else {
        [self nowHideMaskView];
    }
}
#pragma mark -  创建AVPlayer
- (void)setVideoURL:(NSString*)videoURL
{
    _videoURL = videoURL;

    playerView.hidden = NO;

    //一些值都清空还原
    self.playerMaskView.progressView.progress = 0;
    self.playerMaskView.slider.value = 0;
    self.playerMaskView.currentTimeLabel.text = @"00:00";
    self.playerMaskView.totalTimeLabel.text = @"/00:00";
    self.isFailed = NO;
    self.completedPlay = NO;

    //恢复显示maskView及重置数值
    [self showMaskView];

    //每次都关闭定时器 只有readyPlay时才打开
    [self stopTimer];

    //每次都先移除监听
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];

    if (self.playerItem) {
        [self.playerItem removeObserver:self forKeyPath:@"loadedTimeRanges"];
        [self.playerItem removeObserver:self forKeyPath:@"status"];
    }

    //第一次才添加
    if (self.superview == nil) {
        [self.tempSuperView addSubview:self];
    }
    if (self.locationType == LSPLayerViewLocationTypeMiddle) {

        [self.tempSuperView addObserver:self forKeyPath:kLSPlayerViewContentOffset options:NSKeyValueObservingOptionNew context:nil];
        self.monitoring = YES;
    }

    //设置frame
    if (self.isFullScreen) {
        [self updatePlayerViewFrame];
    }
    else {
        if (self.locationType == LSPLayerViewLocationTypeMiddle) {
            self.frame = _currentFrame;
            [self setNeedsLayout];
            [self layoutIfNeeded];
        }
    }

    //第一次才创建
    if (self.playerMaskView == nil) {
        LSPlayerMaskView* playerMaskView = [LSPlayerMaskView playerMaskView];
        [self addSubview:playerMaskView];
        [self bringSubviewToFront:self.retryButton];
        self.playerMaskView = playerMaskView;

        //中间按钮点击事件
        [self.playerMaskView.playButton addTarget:self action:@selector(playOrPause:) forControlEvents:UIControlEventTouchUpInside];

        //全屏按钮点击事件
        [self.playerMaskView.fullButton addTarget:self action:@selector(clickFullScreen) forControlEvents:UIControlEventTouchUpInside];

        //关闭按钮点击事件
        [self.playerMaskView.closeButton addTarget:self action:@selector(closeClick) forControlEvents:UIControlEventTouchUpInside];

        //slider事件
        [self.playerMaskView.slider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
        [self.playerMaskView.slider addTarget:self action:@selector(sliderTouchCancel:) forControlEvents:UIControlEventTouchCancel];
        [self.playerMaskView.slider addTarget:self action:@selector(sliderTouchCancel:) forControlEvents:UIControlEventTouchUpOutside];
        [self.playerMaskView.slider addTarget:self action:@selector(sliderTouchCancel:) forControlEvents:UIControlEventTouchUpInside];
        [self.playerMaskView.slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    }

    //移除原来的layer
    [self.playerLayer removeFromSuperlayer];
    self.playerLayer = nil;
    self.playerItem = nil;

    //只有不在中间时才计算点击cell的位置
    if (self.locationType == LSPLayerViewLocationTypeMiddle) {
        [self handleScrollOffsetWithDict:nil]; //点击时处理位置
    }
    //先暂停
    if (self.player) {
        [self.player pause];
        self.player = nil;
    }

    //创建   item  layer   player
    self.playerItem = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:videoURL]];
    self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];

    //设置屏幕宽高
    if ([self.playerLayer.videoGravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    }
    else {
        self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    }
    [self.layer insertSublayer:self.playerLayer atIndex:0];
    [self setNeedsLayout]; //需手动调一下layoutSubviews

    //播放
    [self.player setRate:1];
    [self.player play];

    //开始加载动画
    [self startAnimation];

    // 监听缓冲进度
    [self.playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
    //监听播放状态
    [self.playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];

    //AVPlayer播放完成通知  item has played to its end time
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlayDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];

    //AVPlayerItemPlaybackStalledNotification media did not arrive in time to continue playback
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stall) name:AVPlayerItemPlaybackStalledNotification object:self.playerItem];

    //    [self testAVPlayerNotification];
}
#pragma mark - slider开始触摸
- (void)sliderTouchDown
{
    [self stopTimer];
}
#pragma mark - slider值改变
- (void)sliderValueChanged:(UISlider*)slider
{
    int time = slider.value * _playerItem.duration.value / _playerItem.duration.timescale;
    self.playerMaskView.currentTimeLabel.text = [self durationStringWithTime:time];
}
#pragma mark - sliderr触摸取消
- (void)sliderTouchCancel:(UISlider*)slider
{

    //拖动改变视频播放进度
    if (_player.status == AVPlayerStatusReadyToPlay) {
        //计算出拖动的当前秒数
        CGFloat total = (CGFloat)_playerItem.duration.value / _playerItem.duration.timescale;
        NSInteger dragedSeconds = floorf(total * slider.value);
        //转换成CMTime才能给player来控制播放进度
        CMTime dragedCMTime = CMTimeMake(dragedSeconds, 1);
        [_player seekToTime:dragedCMTime completionHandler:^(BOOL finish) {
            [self createTimer];
        }];
    }
}

#pragma mark - 重试按钮点击事件
- (void)retryButtonClick:(UIButton*)sender
{
    //相当于重新点击播放按钮重新播放
    self.videoURL = self.videoURL;
}

#pragma mark - 长按手势 处理快进快退 亮度调节
- (void)handleLongGesture:(UILongPressGestureRecognizer*)gesture
{
    CGFloat x = [gesture locationInView:gesture.view].x;
    CGFloat duration = x / self.frame.size.width;
    NSLog(@"duration===%lf", duration);
}

#pragma mark -  蒙版中间按钮点击事件
- (void)playOrPause:(UIButton*)sender
{

    if (sender.selected) {
        [self.player pause];
        [self.timer invalidate];
        self.timer = nil;
    }
    else {
        if (self.isCompletedPlay) {
            self.completedPlay = NO;
            self.videoURL = self.videoURL;
        }
        else {
            [self.player play];
            [self createTimer];
        }
    }
    if (self.locationType == LSPLayerViewLocationTypeBottom) {
        sender.hidden = !sender.selected;
    }
    else {
        [self cancelPreviousPerformAndHideMaskView]; //因为触碰maskView了所以需要将延迟隐藏事件重置为7s
    }
    sender.selected = !sender.selected;
}

#pragma mark - 关闭按钮点击事件
- (void)closeClick
{
    NSLog(@"关闭了了了了了了了了%s", __func__);
    //关闭时一定要停止监听contentOffset

    //注意视频框加入在最上面时已经停止监听了 但是此时重新调用setVideoURL方法又会监听 然后点击关闭按钮 然后滚动tableView还会掉监听方法 移除也不好立刻停止而是毫秒级调用一次
    self.monitoring = NO;
    if (self.isMonitoring) {
        [self.tempSuperView removeObserver:self forKeyPath:kLSPlayerViewContentOffset];
    }
    //重新设置视频框位置为中间
    self.locationType = LSPLayerViewLocationTypeMiddle;
    self.transform = CGAffineTransformIdentity;
    self.playerMaskView.hidden = NO;
    self.playerMaskView.progressView.hidden = NO;
    self.playerMaskView.slider.hidden = NO;
    self.playerMaskView.currentTimeLabel.hidden = NO;
    self.playerMaskView.totalTimeLabel.hidden = NO;

    [self.player pause];
    if (self.superview != self.tempSuperView) {
        [self.tempSuperView addSubview:self];
    }
    playerView.hidden = YES;
    if (self.isFullScreen) {
        [self interfaceOrientation:UIInterfaceOrientationPortrait];
    }
    self.transform = CGAffineTransformIdentity;
}
#pragma mark -  创建定时器
- (void)createTimer
{
    if (self.timer == nil) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(startTime) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
        //                [self.timer fire];
    }
}
#pragma mark - 停止计时器
- (void)stopTimer
{
    if (self.timer) {
        [self.timer invalidate];
        self.timer = nil;
    }
}
#pragma mark - 全屏按钮点击事件
- (void)clickFullScreen
{
    [self cancelPreviousPerformAndHideMaskView];
    if (self.isFullScreen) { //UIInterfaceOrientationPortrait
        [self interfaceOrientation:UIInterfaceOrientationPortrait];
    }
    else {
        [self interfaceOrientation:UIInterfaceOrientationLandscapeRight];
    }
}
- (void)setFullScreen:(BOOL)fullScreen
{
    _fullScreen = fullScreen;
    self.panGesture.enabled = !fullScreen;
    self.pinchGesture.enabled = !fullScreen;
    if (fullScreen) {
        [[UIApplication sharedApplication] setStatusBarHidden:YES];
        self.portraitFrame = self.frame;
        [self handleTimeLabelAndSliderWithHidden:NO];
        self.playerMaskView.playButton.hidden = NO;
        [self updatePlayerViewFrame];
    }
    else {
        if (self.locationType == LSPLayerViewLocationTypeBottom) {
            self.playerMaskView.hidden = NO;
            [self handleTimeLabelAndSliderWithHidden:YES];
        }
        if (self.locationType == LSPLayerViewLocationTypeMiddle) {
            [self.tempSuperView addSubview:self];
        }
        else if (self.locationType == LSPLayerViewLocationTypeTop) {
            //            [self.tempSuperView addSubview:self];
        }
        self.frame = self.portraitFrame;
        [self setNeedsLayout];
        [self layoutIfNeeded];
    }
}
#pragma mark - 立刻显示maskView不执行7s后自动隐藏
- (void)showMaskView
{
    self.playerMaskView.hidden = NO;
    self.hideMaskView = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(nowHideMaskView) object:nil];
}
#pragma mark - 将要显示maskView
- (void)startShowMaskView
{
    if (self.isHideMaskView) {
        [UIView animateWithDuration:0.5 animations:^{
            self.playerMaskView.hidden = NO;
        }
            completion:^(BOOL finished) {
                self.hideMaskView = NO;
                [self cancelPreviousPerformAndHideMaskView];

            }];
    }
}
#pragma mark -重新将延迟事件设置为7s
- (void)cancelPreviousPerformAndHideMaskView
{
    if (self.isHideMaskView)
        return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(nowHideMaskView) object:nil];
    if (self.locationType != LSPLayerViewLocationTypeBottom) {
        [self performSelector:@selector(nowHideMaskView) withObject:nil afterDelay:7];
    }
}

#pragma mark - 隐藏maskView
- (void)nowHideMaskView
{
    if (!self.isHideMaskView) {
        [UIView animateWithDuration:0.5 animations:^{
            self.playerMaskView.hidden = YES;
        }
            completion:^(BOOL finished) {
                self.hideMaskView = YES;

            }];
    }
}

#pragma mark - 横屏frame
- (void)updatePlayerViewFrame
{
    if (self.locationType == LSPLayerViewLocationTypeMiddle) {
        //如果竖屏显示时在中间显示则superView为tableView
        [[UIApplication sharedApplication].keyWindow addSubview:self];
    }
    self.frame = [UIScreen mainScreen].bounds;
    [self setNeedsLayout];
    [self layoutIfNeeded];
}
#pragma mark - 定时器事件
- (void)startTime
{
    NSInteger b = CMTimeGetSeconds([_playerItem currentTime]);
    //    NSLog(@"sss======%ld", b);
    self.playerMaskView.slider.value = CMTimeGetSeconds([_playerItem currentTime]) / (_playerItem.duration.value / _playerItem.duration.timescale); //当前进度

    //当前播放时间
    NSInteger proMin = (NSInteger)CMTimeGetSeconds([_player currentTime]) / 60; //当前秒
    NSInteger proSec = (NSInteger)CMTimeGetSeconds([_player currentTime]) % 60; //当前分钟

    //duration 总时长
    NSInteger durMin = (NSInteger)_playerItem.duration.value / _playerItem.duration.timescale / 60; //总分
    NSInteger durSec = (NSInteger)_playerItem.duration.value / _playerItem.duration.timescale % 60; //总秒

    self.playerMaskView.currentTimeLabel.text = [NSString stringWithFormat:@"%02ld:%02ld", proMin, proSec];
    self.playerMaskView.totalTimeLabel.text = [NSString stringWithFormat:@"/%02ld:%02ld", durMin, durSec];
}
#pragma mark - 显示菊花 并因此播放按钮
- (void)startAnimation
{
    [self.playerMaskView.activity startAnimating];
    self.playerMaskView.activity.hidden = NO;
    self.playerMaskView.playButton.selected = NO;
    self.playerMaskView.playButton.hidden = YES;
}
#pragma mark - 隐藏菊花
- (void)stopAnimation
{
    [self.playerMaskView.activity stopAnimating];
    self.playerMaskView.activity.hidden = YES;
    self.playerMaskView.playButton.hidden = NO;
    self.playerMaskView.playButton.selected = YES;

    if (self.locationType == LSPLayerViewLocationTypeBottom) {
        self.playerMaskView.playButton.hidden = YES;
    }
}

#pragma mark - 播放完成通知事件
- (void)moviePlayDidEnd:(NSNotification*)note
{
    NSLog(@"moviePlayDidEnd");
    //有一个bug就是播放完时间和总时间差1s这里设置为一样
    self.playerMaskView.currentTimeLabel.text = [self.playerMaskView.totalTimeLabel.text substringFromIndex:1];
    [self stopTimer];
    [self showMaskView];
    self.playerMaskView.playButton.selected = NO;
    if (self.locationType == LSPLayerViewLocationTypeBottom) {
        self.playerMaskView.playButton.hidden = NO;
    }
    self.completedPlay = YES;
}
#pragma mark -  监听缓冲进度  KVO
- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary<NSString*, id>*)change context:(void*)context
{
    if ([keyPath isEqualToString:@"status"]) {
        if ([self.playerItem status] == AVPlayerStatusReadyToPlay) { //准备播放
            //            NSLog(@"AVPlayerStatusReadyToPlay");
            [self createTimer];
            [self stopAnimation];
            [self cancelPreviousPerformAndHideMaskView]; //延迟隐藏
            // 转换成秒
            CGFloat totalSecond = self.playerItem.duration.value / self.playerItem.duration.timescale;
            self.playerMaskView.totalTimeLabel.text = [NSString stringWithFormat:@"/%@", [self durationStringWithTime:totalSecond]];
        }
        else if ([self.playerItem status] == AVPlayerStatusFailed) { //播放失败
            //            NSLog(@"AVPlayerStatusFailed");
            [self stopAnimation];
            self.isFailed = YES;
        }
    }
    else if ([keyPath isEqualToString:@"loadedTimeRanges"]) {
        // 计算缓冲进度
        NSTimeInterval timeInterval = [self availableDuration];
        CMTime duration = self.playerItem.duration;
        CGFloat totalDuration = CMTimeGetSeconds(duration);
        CGFloat progress = timeInterval / totalDuration;
        [self.playerMaskView.progressView setProgress:progress];
    }

    if (self.tempSuperView == nil)
        return;
    if (self.locationType != LSPLayerViewLocationTypeMiddle)
        return;
    if (self.isFullScreen)
        return;
    if (!self.isMonitoring)
        return;
    NSLog(@"%s", __func__);
    //此处需要判断全屏时不坚听contentOffset 让不然调用cellForIndexPath会出现崩溃bug
    //竖屏才监听contentOffset
    if ([keyPath isEqualToString:kLSPlayerViewContentOffset]) {
        if (([UIDevice currentDevice].orientation == UIDeviceOrientationLandscapeLeft) || ([UIDevice currentDevice].orientation == UIDeviceOrientationLandscapeRight))
            return;
        [self handleScrollOffsetWithDict:change];
    }
}
#pragma mark - 当tableview滚动时处理playerView的位置
- (void)handleScrollOffsetWithDict:(NSDictionary*)dict
{
    NSLog(@"%s", __func__);
    //测试证明在点击关闭按钮时会掉此方法
    UITableView* tableView = (UITableView*)self.tempSuperView;
    LSPlayerView* playerView = [LSPlayerView playerView];

    UITableViewCell* cell;
    CGRect rect;
    static NSInteger count;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        count = [tableView.dataSource numberOfSectionsInTableView:tableView];
    });
    if (count) { //是多组 每组一行
        cell = [tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:self.index]];
        rect = [tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:self.index]];
    }
    else { //只有一组 多行
        cell = [tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:self.index inSection:0]];
        rect = [tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:self.index inSection:0]];
    }

    CGFloat top = tableView.contentInset.top;
    CGPoint point = tableView.contentOffset;
    CGFloat y = point.y + top;
    if (self.currentFrame.origin.y - y > self.tempSuperView.frame.size.height - CellImageViewHeight) { //在底下
        playerView.locationType = LSPLayerViewLocationTypeBottom;

        [self updataPlayerViewBottomFrame];
        //        NSLog(@"在下面");
    }
    else if (y > rect.origin.y) { //在上面
        playerView.locationType = LSPLayerViewLocationTypeTop;
        //        NSLog(@"在上面");
        [self updataPlayerViewTopFrame];
    }
}
#pragma mark - 底部视频框frame
- (void)updataPlayerViewBottomFrame
{
    CGSize size = [UIScreen mainScreen].bounds.size;
    //计算出tableView在window上的可视位置
    CGRect rect = CGRectIntersection([UIApplication sharedApplication].keyWindow.frame, self.tempSuperView.frame);
    self.frame = CGRectMake(size.width / 2.0, CGRectGetMaxY(rect) - CellImageViewHeight / 2.0, size.width / 2, CellImageViewHeight / 2.0);
    [[UIApplication sharedApplication].keyWindow addSubview:self];
    //强制让系统调用layoutSubviews 两个方法必须同时写
    [self setNeedsLayout]; //是标记 异步刷新 会调但是慢
    [self layoutIfNeeded]; //加上此代码立刻刷新
}
#pragma mark - 顶部视频框frame
- (void)updataPlayerViewTopFrame
{
    [[UIApplication sharedApplication].keyWindow addSubview:self];
    self.frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, CellImageViewHeight);
    //强制让系统调用layoutSubviews 两个方法必须同时写
    [self setNeedsLayout]; //是标记 异步刷新 会调但是慢
    [self layoutIfNeeded]; //加上此代码立刻刷新
}
#pragma mark - 获取缓冲进度
- (NSTimeInterval)availableDuration
{
    NSArray* loadedTimeRanges = [[_player currentItem] loadedTimeRanges];
    CMTimeRange timeRange = [loadedTimeRanges.firstObject CMTimeRangeValue]; // 获取缓冲区域
    float startSeconds = CMTimeGetSeconds(timeRange.start);
    float durationSeconds = CMTimeGetSeconds(timeRange.duration);
    NSTimeInterval result = startSeconds + durationSeconds; // 计算缓冲总进度
    return result;
}
#pragma mark - 根据时长求出字符串

- (NSString*)durationStringWithTime:(int)time
{
    // 获取分钟
    NSString* min = [NSString stringWithFormat:@"%02d", time / 60];
    // 获取秒数
    NSString* sec = [NSString stringWithFormat:@"%02d", time % 60];
    return [NSString stringWithFormat:@"%@:%@", min, sec];
}

#pragma mark 强制转屏相关

- (void)interfaceOrientation:(UIInterfaceOrientation)orientation
{
    self.currentOrientation = orientation;
    // arc下
    if ([[UIDevice currentDevice] respondsToSelector:@selector(setOrientation:)]) {
        SEL selector = NSSelectorFromString(@"setOrientation:");
        NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:[UIDevice instanceMethodSignatureForSelector:selector]];
        [invocation setSelector:selector];
        [invocation setTarget:[UIDevice currentDevice]];
        int val = orientation;
        [invocation setArgument:&val atIndex:2];
        [invocation invoke];
    }
}
#pragma mark - 将失去焦点通知
- (void)willResignActive
{
}
#pragma mark - 进入后台通知
- (void)didEnterBackground
{
}
#pragma mark - 监听设备旋转方向
- (void)listeningRotating
{
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleDeviceOrientationChange) name:UIDeviceOrientationDidChangeNotification object:nil];
}
- (void)handleDeviceOrientationChange
{

    UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
    UIInterfaceOrientation interfaceOrientation = (UIInterfaceOrientation)orientation;
    switch (interfaceOrientation) {

    case UIInterfaceOrientationPortraitUpsideDown: {
        NSLog(@"第3个旋转方向---电池栏在下");

    } break;
    case UIInterfaceOrientationPortrait: {
        NSLog(@"第0个旋转方向---电池栏在上");
        self.fullScreen = NO;

    } break;
    case UIInterfaceOrientationLandscapeLeft: {
        NSLog(@"第2个旋转方向---电池栏在右"); //软件屏幕左右方向和设备左右是反的
        self.fullScreen = YES;

    } break;
    case UIInterfaceOrientationLandscapeRight: {
        self.fullScreen = YES;

    } break;

    default:
        break;
    }
}
#pragma mark - 视频框在底部时隐藏时间label slider
- (void)handleTimeLabelAndSliderWithHidden:(BOOL)hidden
{

    self.playerMaskView.currentTimeLabel.hidden = hidden;
    self.playerMaskView.totalTimeLabel.hidden = hidden;
    self.playerMaskView.slider.hidden = hidden;
    self.playerMaskView.progressView.hidden = hidden;
    self.playerMaskView.closeButton.hidden = NO;
}
- (void)setLocationType:(LSPLayerViewLocationType)locationType
{
    _locationType = locationType;
    switch (locationType) {
    case LSPLayerViewLocationTypeTop: {
        NSLog(@"在上面");
        self.playerMaskView.closeButton.hidden = NO;
        self.panGesture.enabled = YES;
        [[UIApplication sharedApplication] setStatusBarHidden:YES];
        if (self.isMonitoring) {
            [self.tempSuperView removeObserver:self forKeyPath:kLSPlayerViewContentOffset];
        }
        self.monitoring = NO;
        self.pinchGesture.enabled = NO;
        break;
    }
    case LSPLayerViewLocationTypeMiddle: {
        NSLog(@"在中间");
        self.pinchGesture.enabled = NO;
        self.playerMaskView.closeButton.hidden = YES; //当在中间时隐藏关闭按钮
        self.panGesture.enabled = NO;
        [[UIApplication sharedApplication] setStatusBarHidden:NO];
        break;
    }
    case LSPLayerViewLocationTypeBottom: {
        NSLog(@"在底下");
        self.pinchGesture.enabled = YES;
        if (self.isMonitoring) {
            [self.tempSuperView removeObserver:self forKeyPath:kLSPlayerViewContentOffset];
        }
        self.monitoring = NO;
        [[UIApplication sharedApplication] setStatusBarHidden:NO]; //次出会带来contentOffset变化导致在点击关闭按钮时
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(nowHideMaskView) object:nil];
        self.playerMaskView.hidden = NO;
        [self handleTimeLabelAndSliderWithHidden:YES];
        self.playerMaskView.playButton.hidden = YES;
        self.panGesture.enabled = YES;

        break;
    }
    case LSPLayerViewLocationTypeDragging: {

        break;
    }
    }
}
#pragma mark - 高斯模糊
- (UIImage*)imageWithOriginalImage:(UIImage*)originalImage
{
    CIContext* context = [CIContext contextWithOptions:nil];
    CIImage* image = [CIImage imageWithCGImage:originalImage.CGImage];
    CIFilter* filter = [CIFilter filterWithName:@"CIGaussianBlur"];
    [filter setValue:image forKey:kCIInputImageKey];
    [filter setValue:@6.0f forKey:@"inputRadius"];
    CIImage* result = [filter valueForKey:kCIOutputImageKey];
    CGImageRef outImage = [context createCGImage:result fromRect:[result extent]];
    UIImage* blurImage = [UIImage imageWithCGImage:outImage];
    return blurImage;
}
- (void)setCurrentFrame:(CGRect)currentFrame
{
    //高度默认W为图片高度
    currentFrame.size.height = CellImageViewHeight;
    _currentFrame = currentFrame;
}
- (void)setIsFailed:(BOOL)isFailed
{
    _isFailed = isFailed;
    self.retryButton.hidden = !isFailed;
    self.retryTipLabel.hidden = !isFailed;
    if (isFailed) {
        self.playerMaskView.playButton.hidden = YES;
    }
}
- (void)setIsHideMaskView:(BOOL)isHideMaskView
{
    _isHideMaskView = isHideMaskView;
    self.playerMaskView.hidden = isHideMaskView;
}
- (void)stall
{
    [self stopTimer];
    [self stopAnimation];
    self.playerMaskView.playButton.selected = NO;
    self.playerMaskView.playButton.hidden = NO;
    NSLog(@"%s", __func__);
}
#pragma mark - UIGestureDelegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)otherGestureRecognizer
{
    if (gestureRecognizer == self.panGesture && otherGestureRecognizer == self.pinchGesture) {
        return NO;
    }
    if (gestureRecognizer == self.pinchGesture && otherGestureRecognizer == self.panGesture) {
        return NO;
    }
    return YES;
}
- (void)layoutSubviews
{
    [super layoutSubviews];

    self.playerLayer.frame = self.bounds;
    self.playerMaskView.frame = self.bounds;
}
#pragma mark - AVPlayer通知测试

- (void)testAVPlayerNotification
{
    //测试在网络变化过程中通知的发送情况
    //AVPlayerItemTimeJumpedNotification  the item's current time has changed discontinuously
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(jump) name:AVPlayerItemTimeJumpedNotification object:self.playerItem];

    //AVPlayerItemFailedToPlayToEndTimeNotification item has failed to play to its end time
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(failed) name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.playerItem];

    //   //AVPlayerItemNewAccessLogEntryNotification a new access log entry has been added
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accessSuccess) name:AVPlayerItemNewAccessLogEntryNotification object:self.playerItem];

    //AVPlayerItemNewErrorLogEntryNotification  a new error log entry has been added
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accessError) name:AVPlayerItemNewErrorLogEntryNotification object:self.playerItem];

    //AVPlayerItemFailedToPlayToEndTimeErrorKey    // NSError
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(failedToPlay) name:AVPlayerItemFailedToPlayToEndTimeErrorKey object:self.playerItem];
}
- (void)jump
{
    NSLog(@"%s", __func__);
}
- (void)failed
{
    NSLog(@"%s", __func__);
}
- (void)accessSuccess
{
    NSLog(@"%s", __func__);
}
- (void)accessError
{
    NSLog(@"%s", __func__);
}
- (void)failedToPlay
{
    NSLog(@"%s", __func__);
}

@end
