//
//  WebViewController.h
//  Jukebox
//
//  Created by Nik Philipsen on 1/13/17.
//  Copyright © 2017 The Shmansion. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <SpotifyAudioPlayback/SpotifyAudioPlayback.h>

NS_ASSUME_NONNULL_BEGIN

@protocol JukeboxWebViewControllerDelegate;

@interface JukeboxWebViewController : UIViewController<SPTAudioStreamingDelegate, SPTAudioStreamingPlaybackDelegate>

@property (nonatomic, weak, nullable) id <JukeboxWebViewControllerDelegate> delegate;

- (instancetype)initWithURL:(NSURL *)URL;

@end

@protocol JukeboxWebViewControllerDelegate <NSObject>
@optional

/*! @abstract Delegate callback called when the user taps the Done button. Upon this call, the view controller is dismissed modally. */
- (void)webViewControllerDidFinish:(JukeboxWebViewController *)controller;

/*! @abstract Invoked when the initial URL load is complete.
 @param success YES if loading completed successfully, NO if loading failed.
 @discussion This method is invoked when SFSafariViewController completes the loading of the URL that you pass
 to its initializer. It is not invoked for any subsequent page loads in the same SFSafariViewController instance.
 */
- (void)webViewController:(JukeboxWebViewController *)controller didCompleteInitialLoad:(BOOL)didLoadSuccessfully;

@end

NS_ASSUME_NONNULL_END
