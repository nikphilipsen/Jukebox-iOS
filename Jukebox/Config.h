//
//  Config.h
//  Jukebox
//
//  Created by Nik Philipsen on 1/13/17.
//  Copyright © 2017 The Shmansion. All rights reserved.
//

#ifndef Config_h
#define Config_h

// Client ID
//#define kClientId "1070d61ebb6d4824a3728ccaee31bfbf" // Nik's
#define kClientId "e03e15b112774918a9d3dfd5e2e78ba5" // Ryan's

// Jukebox app callback URL
#define kCallbackURL "jukebox-login://callback"

//TODO: add token swap and refresh endpoints

// #define kTokenSwapServiceURL "http://localhost:1234/swap"
// #define kTokenRefreshServiceURL "http://localhost:1234/refresh"

 //#define kTokenSwapServiceURL "https://www.playjuke.com/api/v2/spotify/auth/swap"
 //#define kTokenRefreshServiceURL "https://www.playjuke.com/api/v2/spotify/auth/refresh"

#define kSessionUserDefaultsKey "SpotifySession"


#endif /* Config_h */
