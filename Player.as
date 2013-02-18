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
    import flash.events.NetStatusEvent;
    import flash.events.MouseEvent;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.TimerEvent;
    import flash.media.Video;
    import flash.utils.Timer;

    public class Player extends Sprite
    {
        public var netStream:NetStream;
        public var netConnection:NetConnection;
        public var extNamespace:String;

        public var videoPlayer:Video;
        public var videoDuration:Number;
        public var videoPosition:Number = 0;
        public var videoSize:Number = 0;
        public var videoLoaded:Number = 0;
        public var videoWidth:Number;
        public var videoHeight:Number;
        public var videoAspect:Number;

        public var stageWidth:Number;
        public var stageHeight:Number;
        public var stageAspect:Number;

        public var autoPlay:Boolean = false;
        public var isPlaying:Boolean = false;
        public var hasStarted:Boolean = false;

        public var videoFile:String;
        private var useExternalCall:Boolean = true;
        public var timer:Timer;

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

        public function setupStage():void {
            this.stage.align = StageAlign.TOP_LEFT;
            this.stage.scaleMode = StageScaleMode.NO_SCALE;
            var accuracy:Number = 10;

            stageWidth = this.stage.stageWidth;
            stageHeight = this.stage.stageHeight;
            stageAspect = Math.round( (stageWidth / stageHeight) * accuracy ) / accuracy;

            this.graphics.beginFill(0x000000);
            this.graphics.drawRect(0, 0, stageWidth, stageHeight);
            this.graphics.endFill();
        }

        public function setupPlayer():void {
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
            addChild(videoPlayer);

            this.stage.addEventListener(MouseEvent.MOUSE_OVER,
                                        screenOverHandler);
            this.stage.addEventListener(Event.MOUSE_LEAVE,
                                        screenOutHandler);
            setSize(stageWidth, stageHeight);

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
                    var scaled:Number = 1;

                    var positionPlayer:Boolean = false;

                    if (videoWidth == stageWidth &&
                        videoHeight == stageHeight){
                        setSize(videoWidth, videoHeight);
                    } else if (videoAspect == stageAspect) {
                        setSize(stageWidth, stageHeight);
                        videoPlayer.smoothing = true;
                    } else if (videoAspect > stageAspect) {
                        // video is wider than stage
                        scaled = stageWidth/videoAspect;
                        setSize(stageWidth, Math.round(scaled));
                        videoPlayer.smoothing = true;
                    } else {
                        // video is taller than stage
                        scaled = stageHeight*videoAspect;
                        setSize(scaled, stageHeight);
                        videoPlayer.smoothing = true;
                        positionPlayer = true;
                    }
                    extCall('durationChange', [videoDuration]);
                },

                onPlayStatus: function(info:*):void {
                    stop();
                }

            }
            netStream.client = client;
            videoPlayer.attachNetStream(netStream);
        }

        public function setupTimer():void {
            timer = new Timer(50);
            timer.addEventListener(TimerEvent.TIMER, timedUpdateHandler);
            timer.start()
        }

        public function setupCallbacks():void {
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

        public function timedUpdateHandler(event:TimerEvent):void {
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

        public function setSize(vWidth:Number, vHeight:Number):void {
            videoPlayer.width = vWidth;
            videoPlayer.height = vHeight;
            if (vWidth != stageWidth || vHeight != stageHeight) {
                var lPad:Number = 0;
                var tPad:Number = 0;
                lPad = Math.round( (stageWidth-videoPlayer.width)/2 );
                tPad = Math.round( (stageHeight-videoPlayer.height)/2 );
                videoPlayer.x = lPad;
                videoPlayer.y = tPad;
            } else {
                videoPlayer.x = 0;
                videoPlayer.y = 0;
            }
        }

        public function netStatusHandler(event:NetStatusEvent):void
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

        public function screenOverHandler(event:MouseEvent):void {
            // mouse move events?
        }

        public function screenOutHandler(event:Event):void {
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

        public function reset():void {
            if (isPlaying) {
                stop();
            }
            hasStarted = false;
            netStream.close();
            videoPlayer.clear();
        }

        // UTILITIES

        public function getParam(key:String):String {
            for (var keyStr:String in this.loaderInfo.parameters) {
                if (keyStr == key) {
                    return this.loaderInfo.parameters[keyStr];
                }
            }
            return "";
        }

        public function extCall(method:String, args:Array):void {
            if (ExternalInterface.available && useExternalCall) {
                args.unshift(extNamespace+method);
                ExternalInterface.call.apply(this, args);
            }
        }
    }

}
