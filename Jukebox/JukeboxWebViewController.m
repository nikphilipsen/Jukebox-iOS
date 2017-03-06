//
//  JukeboxWebViewController.m
//  Jukebox
//
//  Created by Nik Philipsen on 1/13/17.
//  Copyright © 2017 The Shmansion. All rights reserved.
//

#import "JukeboxWebViewController.h"
#import <WebKit/WebKit.h>
#import <SpotifyAuthentication/SpotifyAuthentication.h>
#import <SpotifyMetadata/SpotifyMetadata.h>
#import <AVFoundation/AVFoundation.h> // for AVAudioSession
#import <MediaPlayer/MediaPlayer.h> // for setting iOS audio metadata (e.g. what song playing on lock screen)

// define possible actions to do on the playlist
typedef NS_ENUM(NSInteger, PlaylistAction) {
    Continue = 0,
    Play,
    Pause,
    Resume,
    CallPlayNext
};

@interface JukeboxWebViewController () <UIWebViewDelegate, SPTAudioStreamingDelegate>
@property (nonatomic, strong) UIWebView *webView;

// intial view properties
@property (nonatomic, copy) NSURL *initialURL;
@property (nonatomic, assign) BOOL loadComplete;

// managing playlist state w/ threading
@property UIBackgroundTaskIdentifier looperTask;

// playlist info
@property NSString *hostToken;
@property NSString *privateId;
@property NSString *currentSongId;
@property NSString *nextSongId;
@property int durationSeconds;
@property BOOL isPaused;
@property BOOL queuedCallPlayNext;

// spotify player handle
@property (nonatomic, strong) SPTAudioStreamingController *player;
@end

@implementation JukeboxWebViewController

- (instancetype)initWithURL:(NSURL *)URL
{
    self = [super init];
    if (self) {
        _initialURL = [URL copy];
    }
    return self;
    
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // remove whitespace at top of web view
    self.automaticallyAdjustsScrollViewInsets = YES;
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    
    // load initial page provided to the view
    NSURLRequest *initialRequest = [NSURLRequest requestWithURL:self.initialURL];
    self.webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
    self.webView.delegate = self;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.webView];
    [self.webView loadRequest:initialRequest];
    
    [self handleNewSession];
    
    // set playing w/ a background task: this is necessary to continue playback even if the app is put into the background
    [self initializeBackgroundLooper];
    
    // add observer to listen for calls to load a web page
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveEvent:) name:@"loadRequest" object:nil];
    
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
}

// event handler for iOS music controls
-(void)remoteControlReceivedWithEvent:(UIEvent *)event{
    if(event.type == UIEventTypeRemoteControl){
        switch (event.subtype) {
            case UIEventSubtypeRemoteControlPlay:
                [self postPlayNext];
                break;
            case UIEventSubtypeRemoteControlPause:
                [self postPause];
                break;
            case UIEventSubtypeRemoteControlPreviousTrack:
                [self postPrevious];
                break;
            case UIEventSubtypeRemoteControlNextTrack:
                // note: next and play both call this because the server checks if paused to decide if we proceed to next song or just resume
                [self postPlayNext];
                break;
            default:
                break;
        }
    }
}

-(BOOL)canBecomeFirstResponder{
    return YES;
}

// TODO: leaving this here in case we do need to inject JS at some point
-(void)loadAuthTokenWithJavaScript{
//    SPTAuth *auth = [SPTAuth defaultInstance];
//    NSString *token = auth.session.accessToken;
//    NSString *loadAuthTokenInJavascript = [NSString stringWithFormat:@"function loadAuthToken(){\
//                                           if(!Session.get('jukebox-spotify-access-token')){\
//                                            Session.setPersistent('jukebox-spotify-access-token', '%@');\
//                                            location.reload(true);\
//                                           }\
//                                           }\
//                                           loadAuthToken();", token];
//    [self.webView stringByEvaluatingJavaScriptFromString:loadAuthTokenInJavascript];
}

- (void)done
{
    if ([self.delegate respondsToSelector:@selector(webViewControllerDidFinish:)]) {
        [self.delegate webViewControllerDidFinish:self];
    }
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark UIWebViewDelegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    // override host link: we do this so there are no unnecessary redirects and so we can hook into the action directly to
    // start the music
    NSURL *url = [request URL];
    NSString *path = [url path];
    NSString *scheme = [url scheme];
    
    // handle host redirects - when the app tries to go to a host screen, we intercept and initialize the playlist
    // the looper will then start playing
    NSString *hostLinkIndicator = @"/host";
    if (path != nil && [path isEqualToString:hostLinkIndicator]) {
        NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:[request URL]
                                                    resolvingAgainstBaseURL:NO];
        NSArray *queryItems = urlComponents.queryItems;
        NSString *hostToken = [self valueForKey:@"hostToken"
                                 fromQueryItems:queryItems];
        NSString *privateId = [self valueForKey:@"privateId"
                                 fromQueryItems:queryItems];
        
        // re-assign host info if we are passed a host URL
        if(hostToken != nil && privateId != nil){
            @synchronized (self) {
                self.hostToken = hostToken;
                self.privateId = privateId;
                self.queuedCallPlayNext = true; // call play given the new host info
            }
            
            // and then don't actually follow the request, as this will take to the
            // host page to launch/install the app that we are already in...
            return NO;
        }
        return YES;
    }
    
    if(scheme != nil && [scheme isEqualToString:@"jukebox"]){
        // we are already in the app, so don't handle the request
        return NO;
    }
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    if (!self.loadComplete) {
        if ([self.delegate respondsToSelector:@selector(webViewController:didCompleteInitialLoad:)]) {
            [self.delegate webViewController:self didCompleteInitialLoad:YES];
        }
        self.loadComplete = YES;
    }
    
    // disable magnifying glass effect on elements (happens when user holds something and it tries to select it): terrible UX
    for(id subview in self.webView.subviews){
        if([subview isKindOfClass:[UIScrollView class]]){
            UIScrollView *scrollView = (UIScrollView *)subview;
            for(id ssView in scrollView.subviews){
                if([NSStringFromClass([ssView class]) isEqualToString:@"UIWebBrowserView"]){
                    for(UIGestureRecognizer *gs in [ssView gestureRecognizers]){
                        if([gs isKindOfClass:[UILongPressGestureRecognizer class]]){
                            gs.enabled = NO;
                        }
                    }
                }
            }
        }
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    if (!self.loadComplete) {
        if ([self.delegate respondsToSelector:@selector(webViewController:didCompleteInitialLoad:)]) {
            [self.delegate webViewController:self didCompleteInitialLoad:NO];
        }
        self.loadComplete = YES;
    }
}

// receive pages to load
- (void)receiveEvent:(NSNotification *)notification {
    // handle event
    NSURLRequest *requestObj = notification.userInfo[@"requestObj"];
    [self.webView loadRequest:requestObj];
}

// parse string for query parameters
- (NSString *)valueForKey:(NSString *)key
           fromQueryItems:(NSArray *)queryItems
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name=%@", key];
    NSURLQueryItem *queryItem = [[queryItems
                                  filteredArrayUsingPredicate:predicate]
                                 firstObject];
    return queryItem.value;
}

// spawns a background looper process: this (a) manages playlist state by sending POSTs to the web platform
// and (b) preserves our playback processing by instantiating a background task w/ an infinite timeout as long
// as audio is actively playing
- (void) initializeBackgroundLooper
{
    // idempotent
    if(self.looperTask == 0){
        self.looperTask =
        [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            NSLog(@"Looper shutdown");
            [[UIApplication sharedApplication] endBackgroundTask:self.looperTask];
        }];
        
        // setting interval to pretty fast for responsiveness - we will see if this causes complications with battery or threads not finishing faster than that
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.6
                                         target:self
                                       selector:@selector(loopOnce:)
                                       userInfo:nil
                                        repeats:YES];
        // TODO: if we decide it is worth managing shutting down of the thread (outside of its normal shutdown if no audio for some OS-set threshold)
        // then we will need to call this:
        // [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTaskIdentifier];
    
        // since we are not on the MAIN thread, this will get lost when entering background,
        // unless we add directly to MAIN manually here
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
    }
}

// single background loop to manage the playlist
// NOTE: NOT fully thread-safe, and so we are asserting that there only ever is 1 looper at a time.
// There is thread-safety for handling of possible async actions (e.g. track finishing)
- (void) loopOnce:(NSTimer *)timer
{
    // This method might be called when the application is in the background.
    // Ensure you do not do anything that will trigger the GPU (e.g. animations)
    // See: http://developer.apple.com/library/ios/DOCUMENTATION/iPhone/Conceptual/iPhoneOSProgrammingGuide/ManagingYourApplicationsFlow/ManagingYourApplicationsFlow.html#//apple_ref/doc/uid/TP40007072-CH4-SW47
    
    // in the background looper, we:
    // (1) acquire current status
    // (2) state change based on result
    // (3) manage player
    if(self.player != nil && [self.player initialized] == true && self.hostToken != nil && self.privateId != nil){
        [self postGetStatus];
    }
}

-(PlaylistAction) syncState: (NSString*)currentSongId :(NSString*)nextSongId :(BOOL)isPaused :(int)durationInSeconds{
    PlaylistAction action = Continue;
    
    // locking since state changes here should occur without interruption
    @synchronized (self) {
        // handle async queues for calling play next (e.g. for when a track completes and so we must go to next song)
        if(self.queuedCallPlayNext == true){
            action = CallPlayNext;
            self.queuedCallPlayNext = false;
            
            // don't set anything else since post-play they'll potentially be re-assigned anyway
            return action;
        }
        // handle pause transitions
        else if(self.isPaused != isPaused){
            if(isPaused == true){
                action = Pause;
            }
            else{
                action = Resume;
            }
        }
        else{
            // if we have a song and it differs from the current, then call play on it
            if(currentSongId != nil && self.currentSongId != nil){
                if(![currentSongId isEqualToString:self.currentSongId]){
                    action = Play;
                }
            }
            // if the status has a current song ID but we don't then just play that
            else if(self.currentSongId == nil && currentSongId != nil){
                action = Play;
            }
            // otherwise, if we have no songId, then call Play to potentially get one
            else{
                action = CallPlayNext;
            }
        }
        
        self.currentSongId = currentSongId;
        self.nextSongId = nextSongId;
        self.isPaused = isPaused;
        self.durationSeconds = durationInSeconds;
    }
    
    return action;
}

-(void) queuePlayNextCall{
    @synchronized (self) {
        self.queuedCallPlayNext = true;
        self.currentSongId = self.nextSongId;
    }
}

-(void) postPlayNext{
    NSString *urlstring = [NSString stringWithFormat:@"https://www.playjuke.com/api/v2/playlist/play/%@", self.privateId];
    NSURL *url = [NSURL URLWithString:urlstring];
    [self postAsync:url : ^(NSDictionary *dataResponse) {
        if (dataResponse != nil) {
            // TODO: currently ignoring the result here because it is possible that we want to keep looping
            // even if EndOfPlaylist is reached (e.g. if songs are added after we reach the end, OR if we add a reset feature)
        }
    }];
}

-(void) postPause{
    NSString *urlstring = [NSString stringWithFormat:@"https://www.playjuke.com/api/v2/playlist/pause/%@", self.privateId];
    NSURL *url = [NSURL URLWithString:urlstring];
    [self postAsync:url : ^(NSDictionary *dataResponse) {
        if (dataResponse != nil) {
            // we don't need to handle a response because the looper will handle any state changes from the server for this
        }
    }];
}

-(void) postPrevious{
    NSString *urlstring = [NSString stringWithFormat:@"https://www.playjuke.com/api/v2/playlist/previous/%@", self.privateId];
    NSURL *url = [NSURL URLWithString:urlstring];
    [self postAsync:url : ^(NSDictionary *dataResponse) {
        if (dataResponse != nil) {
            /// we don't need to handle a response because the looper will handle any state changes from the server for this
        }
    }];
}

-(void) postGetStatus{
    NSString *urlstring = [NSString stringWithFormat:@"https://www.playjuke.com/api/v2/playlist/status/%@", self.privateId];
    NSURL *url = [NSURL URLWithString:urlstring];
    [self postAsync:url : ^(NSDictionary *dataResponse) {
        if (dataResponse != nil) {
            // responses can come back as NSNull instead of nil, and so we manually handle both here.
            // likely there is a cleaner way to parse this so might want to clean this up
            NSString *currentSongId = dataResponse[@"currentSongId"];
            if((NSNull*)currentSongId == [NSNull null]){
                currentSongId = nil;
            }
            NSString *nextSongId = dataResponse[@"nextSongId"];
            if((NSNull*)nextSongId == [NSNull null]){
                nextSongId = nil;
            }
            NSString *duration = dataResponse[@"durationInSeconds"];
            int durationInSeconds = 30;
            if(duration != nil && (NSNull*)duration != [NSNull null]){
                int seconds = [duration intValue];
                if(seconds > 0){
                    durationInSeconds = seconds;
                }
            }
            NSString *isPaused = dataResponse[@"isPaused"];
            BOOL isPausedBoolean = false;
            if(isPaused != nil){
                isPausedBoolean = [isPaused boolValue];
            }
            NSString *success = dataResponse[@"success"];
            NSString *message = dataResponse[@"message"];
            
            if(success == nil || (NSNull*)success == [NSNull null] || [success boolValue] == false){
                NSLog(@"Unsuccessful playlist status request: %@", message);
                return;
            }
            
            PlaylistAction action = [self syncState:currentSongId :nextSongId :isPausedBoolean :durationInSeconds];
            switch(action){
                case Play:
                    [self playSpotifySong:currentSongId];
                    break;
                case Pause:
                    [self.player setIsPlaying:false callback:nil];
                    break;
                case Resume:
                    if(self.player.metadata.currentTrack == nil){
                        [self playSpotifySong:currentSongId];
                    }
                    [self.player setIsPlaying:true callback:nil];
                    break;
                case CallPlayNext:
                    [self postPlayNext];
                    break;
                case Continue:
                    // no-op
                    break;
                default:
                    NSLog(@"default selected");
                    break;
            }
        }
    }];
}

-(void) postAsync: (NSURL*)url
                :(void (^)(NSDictionary* dataResponse)) successHandler
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    
    NSDictionary *tmp = [[NSDictionary alloc] initWithObjectsAndKeys:
                         self.hostToken, @"hostToken",
                         self.privateId, @"privateId",
                         nil];
    NSError *error;
    NSData *postData = [NSJSONSerialization dataWithJSONObject:tmp options:0 error:&error];
    [request setValue:[NSString stringWithFormat:@"%lu",(unsigned long)[postData length]] forHTTPHeaderField:@"Content-Length"];
    [request setHTTPBody:postData];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error){
        if(error == nil){
            // success: call handler on the result JSON
            NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data
                                                                 options:NSJSONReadingMutableContainers
                                                                   error:&error];
            successHandler(json);
        }
        else{
            // log failure
            NSLog(@"Error talking to Jukebox server: %@", error);
        }
    }];
}

-(void) playSpotifySong:(NSString*)spotifySongId{
    [self.player playSpotifyURI:spotifySongId startingWithIndex:0 startingWithPosition:0 callback:^(NSError *error) {
        if (error != nil) {
            NSLog(@"*** failed to play: %@", error);
            return;
        }
    }];
}

// ---- Spotify SDK ----

// initialize Spotify session
-(void)handleNewSession {
    SPTAuth *auth = [SPTAuth defaultInstance];
    
    if (self.player == nil) {
        NSError *error = nil;
        self.player = [SPTAudioStreamingController sharedInstance];
        if ([self.player startWithClientId:auth.clientID audioController:nil allowCaching:YES error:&error]) {
            self.player.delegate = self;
            self.player.playbackDelegate = self;
            self.player.diskCache = [[SPTDiskCache alloc] initWithCapacity:1024 * 1024 * 64];
            [self.player loginWithAccessToken:auth.session.accessToken];
        } else {
            self.player = nil;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error init" message:[error description] preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            [self closeSession];
        }
    }
}

// close Spotify session
- (void)closeSession {
    NSError *error = nil;
    if (![self.player stopWithError:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error deinit" message:[error description] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    [SPTAuth defaultInstance].session = nil;
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Track Player Delegates

- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didReceiveMessage:(NSString *)message {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Message from Spotify"
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
    [alertView show];
}

- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didChangePlaybackStatus:(BOOL)isPlaying {
    NSLog(@"is playing = %d", isPlaying);
    if (isPlaying) {
        [self activateAudioSession];
    } else {
        [self deactivateAudioSession];
    }
}

// onMetadataChange
-(void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didChangeMetadata:(SPTPlaybackMetadata *)metadata {
}

-(void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didReceivePlaybackEvent:(SpPlaybackEvent)event withName:(NSString *)name {
    NSLog(@"didReceivePlaybackEvent: %zd %@", event, name);
    NSLog(@"isPlaying=%d isRepeating=%d isShuffling=%d isActiveDevice=%d positionMs=%f",
          self.player.playbackState.isPlaying,
          self.player.playbackState.isRepeating,
          self.player.playbackState.isShuffling,
          self.player.playbackState.isActiveDevice,
          self.player.playbackState.position);
}

- (void)audioStreamingDidLogout:(SPTAudioStreamingController *)audioStreaming {
    [self closeSession];
}

- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didReceiveError:(NSError* )error {
    NSLog(@"didReceiveError: %zd %@", error.code, error.localizedDescription);
    
    if (error.code == SPErrorNeedsPremium) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Premium account required" message:@"Premium account is required to showcase application functionality. Please login using premium account." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self closeSession];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        
    }
}

// onSongProgress
- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didChangePosition:(NSTimeInterval)position {
    // proceed when the song is nearly finished
    if(position > self.durationSeconds - 1){
        // immediately play now - time is critical here because if audio stops in the background, it cannot be restored
        if(self.nextSongId != nil){
            [self playSpotifySong: self.nextSongId];
        }
        
        // advance next song and queue call to play next
        [self queuePlayNextCall];
    }
//    else{
//        [[MPNowPlayingInfoCenter defaultCenter] setValue: [NSNumber numberWithDouble:position] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
//    }
}

// onSongStart
- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didStartPlayingTrack:(NSString *)trackUri {
    if ([MPNowPlayingInfoCenter class])  {
        // set iOS music control nowPlayingInfo: song, artist, album, and artwork
        NSURL *imageURL = [NSURL URLWithString:self.player.metadata.currentTrack.albumCoverArtURL];
        if (imageURL == nil) {
            
        }
        
        // pop over to a background queue to load the image over the network.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *error = nil;
            UIImage *image = nil;
            NSData *imageData = [NSData dataWithContentsOfURL:imageURL options:0 error:&error];
            
            if (imageData != nil) {
                image = [UIImage imageWithData:imageData];
            }
            
            
            // …and back to the main queue to display the image.
            dispatch_async(dispatch_get_main_queue(), ^{
                if(image != nil){
                    NSDictionary *currentlyPlayingTrackInfo = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:self.player.metadata.currentTrack.name, self.player.metadata.currentTrack.artistName, self.player.metadata.currentTrack.albumName, [[MPMediaItemArtwork alloc] initWithImage:image], [NSNumber numberWithDouble:self.player.metadata.currentTrack.duration], nil] forKeys:[NSArray arrayWithObjects:MPMediaItemPropertyTitle, MPMediaItemPropertyArtist, MPMediaItemPropertyAlbumTitle, MPMediaItemPropertyArtwork, MPMediaItemPropertyPlaybackDuration, nil]];
                    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = currentlyPlayingTrackInfo;
                }
                else{
                    NSDictionary *currentlyPlayingTrackInfo = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:self.player.metadata.currentTrack.name, self.player.metadata.currentTrack.artistName, self.player.metadata.currentTrack.albumName, [NSNumber numberWithDouble:self.player.metadata.currentTrack.duration], nil] forKeys:[NSArray arrayWithObjects:MPMediaItemPropertyTitle, MPMediaItemPropertyArtist, MPMediaItemPropertyAlbumTitle, MPMediaItemPropertyPlaybackDuration, nil]];
                    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = currentlyPlayingTrackInfo;
                }
            });
        });
        
        // re-auth after each song
        [self renewTokenAndShowPlayer];
    }
//    NSLog(@"Starting %@", trackUri);
//    NSLog(@"Source %@", self.player.metadata.currentTrack.playbackSourceUri);
//    // If context is a single track and the uri of the actual track being played is different
//    // than we can assume that relink has happened.
//    BOOL isRelinked = [self.player.metadata.currentTrack.playbackSourceUri containsString: @"spotify:track"]
//    && ![self.player.metadata.currentTrack.playbackSourceUri isEqualToString:trackUri];
//    NSLog(@"Relinked %d", isRelinked);
}

// onSongFinished
- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didStopPlayingTrack:(NSString *)trackUri {
    NSLog(@"Finishing: %@", trackUri);
    //[self queuePlayNextCall];
}

// onLogin
- (void)audioStreamingDidLogin:(SPTAudioStreamingController *)audioStreaming {
    //[self playNextSong];
}

// re-auth w/ spotify
- (void)renewTokenAndShowPlayer
{
//    SPTAuth *auth = [SPTAuth defaultInstance];
//    
//    [auth renewSession:auth.session callback:^(NSError *error, SPTSession *session) {
//        auth.session = session;
//        
//        if (error) {
//            NSLog(@"*** Error renewing session: %@", error);
//            return;
//        }
//    }];
}

#pragma mark - Audio Session

- (void)activateAudioSession
{
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                           error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
}

- (void)deactivateAudioSession
{
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
}

@end
