package
{
    import flash.external.ExternalInterface;
    import flash.system.Security;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.display.Bitmap;
    import flash.net.NetStream;
    import flash.net.NetConnection;
    import flash.geom.Rectangle;
    import flash.events.NetStatusEvent;
    import flash.events.MouseEvent;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.TimerEvent;
    import flash.events.StageVideoEvent;
    import flash.events.StageVideoAvailabilityEvent;
    import flash.events.VideoEvent;
    import flash.media.Video;
    import flash.media.StageVideo;
    import flash.media.StageVideoAvailability;
    import flash.utils.Timer;

    public class Player extends Sprite
    {
        private var netStream:NetStream;
        private var netConnection:NetConnection;
        private var extNamespace:String;

        private var videoPlayer:Video;
        private var videoDuration:Number;
        private var videoPosition:Number = 0;
        private var videoSize:Number = 0;
        private var videoLoaded:Number = 0;
        private var videoWidth:Number;
        private var videoHeight:Number;
        private var videoAspect:Number;

        private var stageWidth:Number;
        private var stageHeight:Number;
        private var stageAspect:Number;
        private var stageVideo:StageVideo;
        private var stageVideoViewPort:Rectangle = new Rectangle(0, 0, 0, 0);
        private var usingStageVideo:Boolean;
        private var videoRenderState:String;

        private var autoPlay:Boolean = false;
        private var isPlaying:Boolean = false;
        private var hasStarted:Boolean = false;

        private var videoFile:String;
        private var useExternalCall:Boolean = true;
        private var timer:Timer;

        public function Player():void {
            Security.allowDomain("*");
            setupStage();
            setupPlayer();
            setupTimer();
            setupCallbacks();
            extCall('playerLoaded', [videoFile]);
            if (videoFile != "") {
                setSource(videoFile);
            }
        }

        private function setupStage():void {
            stage.align = StageAlign.TOP_LEFT;
            stage.scaleMode = StageScaleMode.NO_SCALE;
            var accuracy:Number = 10;

            stageWidth = videoWidth = stage.stageWidth;
            stageHeight = videoHeight = stage.stageHeight;
            stageAspect = videoAspect = Math.round( (stageWidth / stageHeight) * accuracy ) / accuracy;

            graphics.beginFill(0x000000);
            graphics.drawRect(0, 0, stageWidth, stageHeight);
            graphics.endFill();
        }

        private function setupPlayer():void {
            var autoPlayStr:String = getParam("autoplay");
            if (autoPlayStr == "true") {
                autoPlay = true;
            }

            extNamespace = getParam("namespace");
            if (extNamespace != "") {
                extNamespace += ".";
            }
            videoFile = getParam("video");
            videoPlayer = new Video();
            stage.addEventListener(StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY,
                onStageVideoAvailabilityChange);
            videoPlayer.addEventListener(VideoEvent.RENDER_STATE, onVideoRenderStateChange);
            stage.addEventListener(Event.RESIZE, onResize);
            stage.addEventListener(MouseEvent.MOUSE_OVER,
                                        screenOverHandler);
            stage.addEventListener(Event.MOUSE_LEAVE,
                                        screenOutHandler);

            netConnection = new NetConnection();
            netConnection.addEventListener(NetStatusEvent.NET_STATUS,
                                           netStatusHandler);
            netConnection.connect(null);
            netStream = new NetStream(netConnection);
            netStream.addEventListener(NetStatusEvent.NET_STATUS,
                                       netStatusHandler);
            netStream.bufferTime = 1;

            var client:Object = {
                onMetaData: function(info:*):void {
                    var accuracy:Number = 10;
                    videoDuration = info.duration;
                    videoSize = netStream.bytesTotal;
                    videoWidth = info.width;
                    videoHeight = info.height;
                    videoAspect = Math.round( (videoWidth / videoHeight ) * accuracy ) / accuracy;
                    resize();
                    extCall('durationChange', [videoDuration]);
                },

                onPlayStatus: function(info:*):void {
                    stop();
                }

            }
            netStream.client = client;
            //videoPlayer.attachNetStream(netStream);
            resize();
        }

        private function onResize(resizeEvent:Event):void {
            resize();
        }

        private function resize():void {
            var accuracy:Number = 10;
            stageWidth = stage.stageWidth;
            stageHeight = stage.stageHeight;
            stageAspect = Math.round( (stageWidth / stageHeight) * accuracy ) / accuracy;
            setSize(stageWidth, stageHeight);
        }

        private function onStageVideoAvailabilityChange(stageEvent:StageVideoAvailabilityEvent):void {
            var wasUsingStageVideo:Boolean = usingStageVideo == true;
            usingStageVideo = stageEvent.availability == StageVideoAvailability.AVAILABLE;
            extCall("log", ["STAGE VIDEO AVAILABLE: " + usingStageVideo]);
            if (usingStageVideo) {
                if (stageVideo == null) {
                    stageVideo = stage.stageVideos[0];
                    stageVideo.addEventListener(StageVideoEvent.RENDER_STATE, onStageVideoRenderStateChange);
                }
                stageVideo.attachNetStream(netStream);
                if (!wasUsingStageVideo) {
                    // stage video has become available
                    stage.removeChild(videoPlayer);
                }
            } else {
                videoPlayer.attachNetStream(netStream);
                stage.addChild(videoPlayer);
            }
        }

        private function onStageVideoRenderStateChange(stageVideoEvent:StageVideoEvent):void {
            resize();
            extCall("log", ["STAGE RENDER STATE: " + stageVideoEvent.status]);
        }

        private function onVideoRenderStateChange(videoEvent:VideoEvent):void {
            resize();
            extCall("log", ["RENDER STATE: " + videoEvent.status]);
        }

        private function setupTimer():void {
            timer = new Timer(50);
            timer.addEventListener(TimerEvent.TIMER, timedUpdateHandler);
            timer.start()
        }

        private function setupCallbacks():void {
            if (ExternalInterface.available) {
                try {
                    ExternalInterface.addCallback("setSource", setSource);
                    ExternalInterface.addCallback("play", play);
                    ExternalInterface.addCallback("pause", pause);
                    ExternalInterface.addCallback("seek", seek);
                } catch (error:Error) {
                    extCall("playerError", ["Could not set up callbacks: " + error.message]);
                }
            }
        }

        private function timedUpdateHandler(event:TimerEvent):void {
            if (netStream.bytesLoaded != videoLoaded) {
                videoLoaded = netStream.bytesLoaded;
                var bufferPercent:Number = videoLoaded / videoSize;
                extCall("playBuffered", [bufferPercent]);
            }
            if (isPlaying && netStream.time != videoPosition) {
                videoPosition = netStream.time;
                var percent:Number = videoPosition / videoDuration;
                extCall("playProgress", [percent]);
                extCall("currentTime", [videoPosition]);
            }
        }

        public function setSource(source:String):void {
            if (isPlaying || hasStarted) {
                stop();
                reset();
            }
            if (source && source != "") {
                videoFile = source;
            }
            if (autoPlay) {
                play();
            }
        }

        public function setSize(newWidth:Number, newHeight:Number):void {

            var smoothing:Boolean = false;
            var leftPadding:Number = 0;
            var topPadding:Number = 0;

            if (videoWidth == stageWidth &&
                videoHeight == stageHeight){
                newWidth = videoWidth;
                newHeight = videoHeight;
            } else if (videoAspect == stageAspect) {
                smoothing = true;
            } else if (videoAspect > stageAspect) {
                // video is wider than stage
                newHeight = Math.round(stageWidth / videoAspect);
                newWidth = stageWidth;
                smoothing = true;
            } else {
                // video is taller than stage
                newWidth = stageHeight * videoAspect;
                newHeight = stageHeight;
                smoothing = true;
            }
            if (newWidth != stageWidth || newHeight != stageHeight) {
                leftPadding = Math.round( (stageWidth-videoPlayer.width)/2 );
                topPadding = Math.round( (stageHeight-videoPlayer.height)/2 );
            }
            extCall("log", ["NEW PIXELS: " + newWidth + "x" + newHeight + ", (" + leftPadding + ", " + topPadding + ")"]);
            if (usingStageVideo) {
                stageVideoViewPort.x = leftPadding;
                stageVideoViewPort.y = topPadding;
                stageVideoViewPort.width = newWidth;
                stageVideoViewPort.height = newHeight;
                stageVideo.viewPort = stageVideoViewPort;
            } else {
                videoPlayer.x = leftPadding;
                videoPlayer.y = topPadding;
                videoPlayer.width = newWidth;
                videoPlayer.height = newHeight;
                videoPlayer.smoothing = smoothing;
            }
        }

        private function netStatusHandler(event:NetStatusEvent):void
        {
            switch(event.info.code) {
                case "NetStream.Play.StreamNotFound":
                    extCall("playerError", ["Requested video stream not found."]);
                break;

                case "NetStream.Play.Start":
                    hasStarted = true;
                    isPlaying = true;
                break;

                case "NetStream.Play.Stop":
                    stop();
                break;
            }
        }

        // OSD Handlers

        private function screenOverHandler(event:MouseEvent):void {
            // mouse move events?
        }

        private function screenOutHandler(event:Event):void {
            // mouse move events?
        }

        // Play Control Functions

        public function play():void
        {
            if (hasStarted) {
                isPlaying = true;
                videoPlayer.alpha = 1;
                netStream.resume();
            } else if (videoFile) {
                videoPlayer.alpha = 1;
                netStream.play(videoFile);
                extCall("play", [escape(videoFile)]);
            } else {
                extCall("playerError", ["No video file to play."])
            }
        }

        public function pause():void
        {
            isPlaying = false;
            netStream.pause();
            extCall("pause", []);
        }

        public function stop():void {
            isPlaying = false;
            hasStarted = false;
            videoPlayer.clear();
            videoPlayer.alpha = 0;
            netStream.pause();
            netStream.seek(0);
            extCall("stop", []);
        }

        public function seek(seekTime:Number):void {
            if (!hasStarted) {
                extCall("playerError", ["Video has not started -- cannot seek."])
                return;
            }
            if (seekTime > videoDuration) {
                seekTime = videoDuration;
            } else if (seekTime < 0) {
                seekTime = 0;
            }
            netStream.seek(seekTime);
            // this is a bit dishonest, considering keyframes, etc...
            extCall("playProgress", [seekTime / videoDuration]);
            extCall("currentTime", [seekTime]);
        }

        private function reset():void {
            if (isPlaying) {
                stop();
            }
            hasStarted = false;
            netStream.close();
            videoPlayer.clear();
        }

        // UTILITIES

        private function getParam(key:String):String {
            for (var keyStr:String in loaderInfo.parameters) {
                if (keyStr == key) {
                    return loaderInfo.parameters[keyStr];
                }
            }
            return "";
        }

        private function extCall(method:String, args:Array):void {
            if (ExternalInterface.available && useExternalCall) {
                args.unshift(extNamespace+method);
                ExternalInterface.call.apply(this, args);
            }
        }
    }

}
