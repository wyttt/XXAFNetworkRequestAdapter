//
//  XXAFNetworkResponse.h
//  XXAFNetworkRequestAdapter
//
//  Created by Shawn on 2019/3/12.
//  Copyright © 2019 Shawn. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XXResponse.h>

@interface XXAFNetworkResponse : NSObject<XXResponse>

@property (nonatomic) NSInteger statusCode;

@property (nonatomic, strong) id responseObject;

@property (nonatomic, strong) NSError *error;

@end
