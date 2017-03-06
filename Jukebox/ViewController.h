//
//  ViewController.h
//  Jukebox
//
//  Created by Nik Philipsen on 1/13/17.
//  Copyright © 2017 The Shmansion. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <SpotifyAudioPlayback/SpotifyAudioPlayback.h>

@interface ViewController : UIViewController<SPTAudioStreamingDelegate, SPTAudioStreamingPlaybackDelegate>

@property(nonatomic) NSString *partyId;
@property(nonatomic) NSString *privateId;
@property(nonatomic) NSString *hostToken;

@end
