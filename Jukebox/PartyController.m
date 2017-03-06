//
//  PartyController.m
//  Jukebox
//
//  Created by Nik Philipsen on 1/14/17.
//  Copyright © 2017 The Shmansion. All rights reserved.
//

#import "PartyController.h"
#import <SpotifyAuthentication/SpotifyAuthentication.h>
#import <SpotifyMetadata/SpotifyMetadata.h>
#import <SpotifyAudioPlayback/SpotifyAudioPlayback.h>
#import "Config.h"

#import <SafariServices/SafariServices.h>
#import <WebKit/WebKit.h>
#import "WebViewController.h"

@interface PartyController () <SFSafariViewControllerDelegate, WebViewControllerDelegate>


@end

@implementation PartyController


#pragma mark - View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.partyStatusLabel.text = @"";
    [self.PartyIdEntry becomeFirstResponder];

}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    // Else, just show login dialog
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

/*
- (IBAction)PartyIdEntry:(id)sender {
    UITextField *PartyIdField = sender;
    NSLog( @"text changed: %@", PartyIdField.text);
    if(PartyIdField.text.length == 4) {
        if([self checkParty:PartyIdField.text]) {
            [self showPlayer];
        } else {
            self.partyStatusLabel.text = @"Party doesn't exist. Try again?";
            PartyIdField.text = nil;
        }
    }

}
*/

- (IBAction)GoPartyButton:(id)sender {
    if([self checkParty:self.PartyIdEntry.text]) {
        self.partyId = self.PartyIdEntry.text;
        [self showPlayer];
    } else {
        self.partyStatusLabel.text = @"Party doesn't exist. Try again?";
        self.PartyIdEntry.text = nil;
    }
}


- (BOOL)checkParty:(NSString*)partyId {
    
    NSString *url = [NSString stringWithFormat:@"%@%@", @"http://35.167.240.82/api/playlist/isvalid/", partyId];
    NSLog(@"API request: %@",url);
    NSURLRequest *Request = [NSURLRequest requestWithURL:[NSURL URLWithString: url]];
    NSURLResponse *resp = nil;
    NSError *error = nil;
    NSData *response = [NSURLConnection sendSynchronousRequest: Request returningResponse: &resp error: &error];
    id responseObject = [NSJSONSerialization JSONObjectWithData:response options: NSJSONReadingMutableContainers error:&error];
    NSLog(@"API (api/playlist/isvalid) response: %@",responseObject);
    
        if ([responseObject[@"isValid"] isEqualToString:@"true"]) {
            return true;
        } else {
            NSLog(@"*** Failed to find party");
            return false;
        }

    
}


- (void)sessionUpdatedNotification:(NSNotification *)notification
{
}

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender{
    if([segue.identifier isEqualToString:@"ShowPlayer"]){
        ViewController *controller = (ViewController *)segue.destinationViewController;
        controller.partyId = self.partyId;
    }
}

- (void)showPlayer
{
    self.partyStatusLabel.text = @"Getting this party started!";
    [self performSegueWithIdentifier:@"ShowPlayer" sender:nil];
}


@end
