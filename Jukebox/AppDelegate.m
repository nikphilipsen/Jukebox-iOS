//
//  AppDelegate.m
//  Jukebox
//
//  Created by Nik Philipsen on 1/13/17.
//  Copyright © 2017 The Shmansion. All rights reserved.
//

#import "AppDelegate.h"
#import <SpotifyAuthentication/SpotifyAuthentication.h>
#import <SpotifyMetadata/SpotifyMetadata.h>
#import <SpotifyAudioPlayback/SpotifyAudioPlayback.h>
#import "Config.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Set up shared authentication information
    SPTAuth *auth = [SPTAuth defaultInstance];
    auth.clientID = @kClientId;
    auth.requestedScopes = @[SPTAuthStreamingScope];
    auth.redirectURL = [NSURL URLWithString:@kCallbackURL];
#ifdef kTokenSwapServiceURL
    auth.tokenSwapURL = [NSURL URLWithString:@kTokenSwapServiceURL];
#endif
#ifdef kTokenRefreshServiceURL
    auth.tokenRefreshURL = [NSURL URLWithString:@kTokenRefreshServiceURL];
#endif
    auth.sessionUserDefaultsKey = @kSessionUserDefaultsKey;
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {

    NSLog(@"URL scheme: %@", [url scheme]);
    NSLog(@"URL query: %@", [url query]);
    NSLog(@"URL path: %@", [url path]);
    
    // parse query params
    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:url
                                                resolvingAgainstBaseURL:NO];
    NSArray *queryItems = urlComponents.queryItems;
    NSString *hostToken = [self valueForKey:@"hostToken"
                          fromQueryItems:queryItems];
    NSString *privateId = [self valueForKey:@"privateId"
                             fromQueryItems:queryItems];
    
    // if we were passed a URL w/ token and playlist ID, then load the playlist (host link)
    if(hostToken != nil && privateId != nil){
        NSLog(@"URL hostToken: %@", hostToken);
        NSString *url = [NSString stringWithFormat:@"https://www.playjuke.com/p/%@/?hostToken=%@", privateId, hostToken];
        NSURL *jukeHostPage = [NSURL URLWithString: url];
        
        // notify web view to load the new URL
        NSURLRequest *requestObj = [NSURLRequest requestWithURL:jukeHostPage];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"loadRequest"
                                                            object:nil
                                                          userInfo:@{@"requestObj":requestObj}];
    }
    
    // if we are passed a jukebox URL w/ just private ID, then we join the playlist (join link)
    NSString *jukeboxScheme = @"jukebox";
    if([[url scheme] isEqualToString:jukeboxScheme]){
        NSLog(@"Jukebox app URL");
        
        NSString *playlistId = [self valueForKey:@"playlistId"
                                 fromQueryItems:queryItems];
        
        if(playlistId != nil){
            NSString *url = [NSString stringWithFormat:@"https://www.playjuke.com/p/%@", playlistId];
            NSURL *jukeJoinPage = [NSURL URLWithString: url];
            
            // notify web view to load the new URL
            NSURLRequest *requestObj = [NSURLRequest requestWithURL:jukeJoinPage];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"loadRequest"
                                                                object:nil
                                                              userInfo:@{@"requestObj":requestObj}];
        }
    }

    SPTAuth *auth = [SPTAuth defaultInstance];
    
    SPTAuthCallback authCallback = ^(NSError *error, SPTSession *session) {
        // This is the callback that'll be triggered when auth is completed (or fails).
        
        if (error) {
            NSLog(@"*** Auth error: %@", error);
        } else {
            auth.session = session;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"sessionUpdated" object:self];
    };
    
    /*
     Handle the callback from the authentication service. -[SPAuth -canHandleURL:]
     helps us filter out URLs that aren't authentication URLs (i.e., URLs you use elsewhere in your application).
     */
    
    if ([auth canHandleURL:url]) {
        [auth handleAuthCallbackWithTriggeredAuthURL:url callback:authCallback];
        return YES;
    }
    
    
//    if ([[url query] rangeOfString:@"hostToken"].location == NSNotFound) {
//    }
//    
//        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
//        ViewController *controller=[storyboard instantiateViewControllerWithIdentifier:@"MusicViewController"];
//        controller.partyId = [[url query] stringByRemovingPercentEncoding];
//        NSLog(@"partyId: %@", controller.partyId);
//        [self.window.rootViewController.navigationController pushViewController:controller animated:YES];
//        
//        return YES;
    

    
    return NO;
}

- (NSString *)valueForKey:(NSString *)key
           fromQueryItems:(NSArray *)queryItems
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name=%@", key];
    NSURLQueryItem *queryItem = [[queryItems
                                  filteredArrayUsingPredicate:predicate]
                                 firstObject];
    return queryItem.value;
}


@end
