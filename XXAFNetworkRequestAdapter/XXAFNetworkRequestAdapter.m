//
//  XXAFNetworkRequestAdapter.m
//  XXAFNetworkRequestAdapter
//
//  Created by Shawn on 2019/3/12.
//  Copyright © 2019 Shawn. All rights reserved.
//

#import "XXAFNetworkRequestAdapter.h"
#import <AFNetworking.h>
#import <XXHTTPRequestURLEncodingSerializer.h>
#import <XXHTTPRequestJSONSerializer.h>
#import <XXHTTPResponseJSONSerializer.h>
#import "NSURLSessionTask+XXRequestOpration.h"
#import "XXAFNetworkResponse.h"

typedef void (^XXAFNetworkRequestCompletion)(NSURLSessionDataTask *task, id responseObject);

@interface XXAFNetworkRequestAdapter ()
{
    NSMutableDictionary *requestManagerDictionary;
    NSRecursiveLock *lock;
    AFHTTPSessionManager *httpSessionManager;
    dispatch_queue_t completionQueue;
}

@end

@implementation XXAFNetworkRequestAdapter

- (instancetype)init
{
    self = [super init];
    if (self) {
        lock = [NSRecursiveLock new];
        requestManagerDictionary = [NSMutableDictionary dictionary];
        completionQueue = dispatch_queue_create([[NSString stringWithFormat:@"com.shawn.network.%p",self] UTF8String], DISPATCH_QUEUE_SERIAL);
        httpSessionManager = [AFHTTPSessionManager manager];
        httpSessionManager.completionQueue = completionQueue;
    }
    return self;
}

- (id<XXRequestOperation>)sendRequest:(id<XXRequest>)request successCompletion:(XXHTTPRequestHandleCompletion)completion
{
    AFHTTPSessionManager *mgr = [self mgrForRequest:request];
    if (mgr == nil) {
        mgr = httpSessionManager;
    }
    
    NSString *URLPath = request.URLString;
    if ([URLPath length] > 0 && [[URLPath substringToIndex:1] isEqualToString:@"/"]) {
        URLPath = [URLPath substringFromIndex:1];
    }
    
    NSDictionary *headers = nil;
    if ([(NSObject *)request respondsToSelector:@selector(headers)]) {
        headers = [request headers];
    }
    
    for (NSString *tempKey in headers.allKeys) {
        [mgr.requestSerializer setValue:headers[tempKey] forHTTPHeaderField:tempKey];
    }
    
    NSDictionary *parameter = nil;
    if ([(NSObject *)request respondsToSelector:@selector(parameter)]) {
        parameter = [request parameter];
    }
    
    NSString *method = [request.HTTPMethod lowercaseString];
    BOOL isForm = NO;
    if ([(NSObject *)request respondsToSelector:@selector(formBodyParts)]) {
        NSArray *formBodys = [request formBodyParts];
        if (formBodys.count > 0) {
            isForm = YES;
        }
    }
    
    XXAFNetworkRequestCompletion successBlock = ^(NSURLSessionDataTask *task, id responseObject) {
        XXAFNetworkResponse *tempResponse = [XXAFNetworkResponse new];
        tempResponse.statusCode = [(NSHTTPURLResponse *)task.response statusCode];
        tempResponse.responseObject = responseObject;
        if (completion) {
            completion(tempResponse);
        }
    };
    
    XXAFNetworkRequestCompletion failedBlock = ^(NSURLSessionDataTask *task, NSError *error) {
        XXAFNetworkResponse *tempResponse = [XXAFNetworkResponse new];
        tempResponse.statusCode = [(NSHTTPURLResponse *)task.response statusCode];
        tempResponse.error = error;
        if (completion) {
            completion(tempResponse);
        }
    };
    
    NSURLSessionTask *task = nil;
    if (isForm) {
        task = [mgr POST:URLPath parameters:parameter constructingBodyWithBlock:^(id<AFMultipartFormData>  _Nonnull formData) {
            NSArray *formBodys = [request formBodyParts];
            for (id<XXPostFormBodyPart> tempPart in formBodys) {
                NSString *name = [tempPart partName];
                NSString *mimeType = nil;
                if ([tempPart respondsToSelector:@selector(partMimeType)]) {
                    mimeType = [tempPart partMimeType];
                }
                NSString *fileName = nil;
                if ([tempPart respondsToSelector:@selector(partFileName)]) {
                    fileName = [tempPart partFileName];
                }
                if (fileName) {
                    [formData appendPartWithFileData:[tempPart partData] name:name fileName:fileName mimeType:mimeType];
                }else
                {
                    [formData appendPartWithFormData:[tempPart partData] name:name];
                }
            }
            
        } progress:nil success:successBlock failure:failedBlock];
    }else
    {
        if ([method isEqualToString:@"get"]) {
            return [mgr GET:URLPath parameters:parameter progress:nil success:successBlock failure:failedBlock];
        }else if ([method isEqualToString:@"post"])
        {
            return [mgr POST:URLPath parameters:parameter progress:nil success:successBlock failure:failedBlock];
        }else
        {
            NSURLRequest *tempURLRequest = [request.requestSerializer serializerRequest:request];
            task = [mgr dataTaskWithRequest:tempURLRequest uploadProgress:nil downloadProgress:nil completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
                XXAFNetworkResponse *tempResponse = [XXAFNetworkResponse new];
                tempResponse.statusCode = [(NSHTTPURLResponse *)response statusCode];
                tempResponse.error = error;
                tempResponse.responseObject = responseObject;
                if (completion) {
                    completion(tempResponse);
                }
            }];
            [task resume];
        }
    }
    
    for (NSString *tempKey in headers.allKeys) {
        [mgr.requestSerializer setValue:nil forHTTPHeaderField:tempKey];
    }
    return task;
}

- (void)_addRequestSessionManager:(AFHTTPSessionManager *)mgr key:(NSString *)key
{
    if (key == nil || mgr == nil) {
        return;
    }
    [lock lock];
    requestManagerDictionary[key] = mgr;
    [lock unlock];
}

- (AFHTTPSessionManager *)mgrForRequest:(id<XXRequest>)request
{
    if (request == nil) {
        return nil;
    }
    NSMutableString *tempKey = [NSMutableString string];
    [tempKey appendString:request.baseURL];
    if ([(NSObject *)request respondsToSelector:@selector(requestSerializer)] == NO) {
        return nil;
    }
    if ([(NSObject *)request respondsToSelector:@selector(responseSerializer)] == NO) {
        return nil;
    }
    if (request.requestSerializer == nil || request.responseSerializer == nil) {
        return nil;
    }
    [tempKey appendFormat:@"__%@__%@",NSStringFromClass([request.requestSerializer class]),NSStringFromClass([request.responseSerializer class])];
    AFHTTPSessionManager *mgr = [self mgrForKey:tempKey];
    if (mgr == nil) {
        mgr = [[AFHTTPSessionManager alloc]initWithBaseURL:[NSURL URLWithString:request.baseURL]];
        if ([request.requestSerializer isKindOfClass:[XXHTTPRequestJSONSerializer class]]) {
            mgr.requestSerializer = [AFJSONRequestSerializer serializer];
        }
        if ([request.responseSerializer isKindOfClass:[XXHTTPResponseJSONSerializer class]]) {
            mgr.responseSerializer = [AFJSONResponseSerializer serializer];
        }
        mgr.completionQueue = completionQueue;
        mgr.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"application/json", @"text/json", @"text/javascript",@"text/html", @"text/plain",@"application/atom+xml",@"application/xml",@"text/xml",@"application/x-www-form-urlencoded", nil];
        [self _addRequestSessionManager:mgr key:tempKey];
    }
    return mgr;
}

- (AFHTTPSessionManager *)mgrForKey:(NSString *)key
{
    [lock lock];
    AFHTTPSessionManager *mgr = requestManagerDictionary[key];
    [lock unlock];
    return mgr;
}
@end
