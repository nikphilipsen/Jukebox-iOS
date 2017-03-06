//
//  JukeboxViewController.m
//  Jukebox
//
//  Created by Nik Philipsen on 2/20/17.
//  Copyright © 2017 The Shmansion. All rights reserved.
//

#import "JukeboxViewController.h"
#import "JukeboxWebViewController.h"
#import <SpotifyAuthentication/SpotifyAuthentication.h>
#import <SpotifyMetadata/SpotifyMetadata.h>

@interface JukeboxViewController () <JukeboxWebViewControllerDelegate>

@property (atomic, readwrite) UIViewController *jukeboxViewController;

@end

@implementation JukeboxViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    UIViewController *viewController;
    SPTAuth *auth = [SPTAuth defaultInstance];
    NSString *url = [NSString stringWithFormat:@"https://www.playjuke.com/spotify/auth#access_token=%@", auth.session.accessToken];
    NSURL *jukeDefaultPage = [NSURL URLWithString:url];
    JukeboxWebViewController *webView = [[JukeboxWebViewController alloc] initWithURL:jukeDefaultPage];
    webView.delegate = self;
    viewController = [[UINavigationController alloc] initWithRootViewController:webView];
    viewController.modalPresentationStyle = UIModalPresentationPageSheet;
    self.jukeboxViewController = viewController;
    [self presentViewController:self.jukeboxViewController animated:YES completion:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}


#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}

@end
