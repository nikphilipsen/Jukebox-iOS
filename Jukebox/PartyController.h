//
//  PartyController.h
//  Jukebox
//
//  Created by Nik Philipsen on 1/14/17.
//  Copyright © 2017 The Shmansion. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "ViewController.h"

@interface PartyController : UIViewController <UITextFieldDelegate>
{
    IBOutlet UILabel *statusLabel;
    IBOutlet UITextField *PartyIdEntry;
}

@property (weak, nonatomic) IBOutlet UILabel *partyStatusLabel;
@property (weak, nonatomic) IBOutlet UITextField *PartyIdEntry;
@property(nonatomic) NSString *partyId;


@end
