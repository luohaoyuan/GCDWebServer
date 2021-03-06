/*
 Copyright (c) 2012-2019, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * The name of Pierre-Olivier Latour may not be used to endorse
 or promote products derived from this software without specific
 prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL PIERRE-OLIVIER LATOUR BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#if !__has_feature(objc_arc)
#error GCDWebUploader requires ARC
#endif

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <SystemConfiguration/SystemConfiguration.h>
#endif

#import "GCDWebUploader.h"
#import "GCDWebServerDataRequest.h"
#import "GCDWebServerMultiPartFormRequest.h"
#import "GCDWebServerURLEncodedFormRequest.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerErrorResponse.h"
#import "GCDWebServerFileResponse.h"

NS_ASSUME_NONNULL_BEGIN
@interface GCDWebUploader () {
@private
    NSString *_uploadDirectory;
    NSArray *_allowedExtensions;
    BOOL _allowHidden;
    NSString *_title;
    NSString *_header;
    NSString *_prologue;
    NSString *_epilogue;
    NSString *_footer;
}
@end
NS_ASSUME_NONNULL_END

@implementation GCDWebUploader

@synthesize uploadDirectory = _uploadDirectory, allowedFileExtensions = _allowedExtensions, allowHiddenItems = _allowHidden,
title = _title, header = _header, prologue = _prologue, epilogue = _epilogue, footer = _footer;

@dynamic delegate;

- (instancetype)initWithUploadDirectory:(NSString *)path {
    if ((self = [super init])) {
        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"GCDWebUploader" ofType:@".bundle"];
        NSBundle *siteBundle = [NSBundle bundleWithPath:bundlePath];
        
        if (siteBundle == nil) {
            return nil;
        }
        _uploadDirectory = [[path stringByStandardizingPath] copy];
        GCDWebUploader *__unsafe_unretained server = self;
        
        // Resource files
        [self addGETHandlerForBasePath:@"/" directoryPath:[siteBundle resourcePath] indexFilename:nil cacheAge:3600 allowRangeRequests:NO];
        
        // Web page
        [self addHandlerForMethod:@"GET"
                             path:@"/"
                     requestClass:[GCDWebServerRequest class]
                     processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                         
                         NSString *title = server.title;
                         if (title == nil) {
                             title = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
                             if (title == nil) {
                                 title = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
                             }
#if !TARGET_OS_IPHONE
                             if (title == nil) {
                                 title = [[NSProcessInfo processInfo] processName];
                             }
#endif
                         }
                         NSString *header = server.header;
                         if (header == nil) {
                             header = title;
                         }
                         NSString *footer = ({
                             NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
                             [NSString stringWithFormat:@"NeatReader %@ NeatReader版权所有 Copyright © 2016-2018", version];
                         });
                         
                         return [GCDWebServerDataResponse responseWithHTMLTemplate:[siteBundle pathForResource:@"index" ofType:@"html"]
                                                                         variables:@{ @"title": title,
                                                                                      @"header": header,
                                                                                      @"footer": footer,
                                                                                      @"validateformat": server.validateFileExtensionJS }];
                         
                     }];
        
        // File listing
        [self addHandlerForMethod:@"GET"
                             path:@"/files"
                     requestClass:[GCDWebServerRequest class]
                     processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                         return [server listDirectory:request];
                     }];
        
        // File download
        [self addHandlerForMethod:@"GET"
                             path:@"/download"
                     requestClass:[GCDWebServerRequest class]
                     processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                         return [server downloadFile:request];
                     }];
        
        // File upload
        [self addHandlerForMethod:@"POST"
                             path:@"/upload"
                     requestClass:[GCDWebServerMultiPartFormRequest class]
                     processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                         return [server uploadFile:(GCDWebServerMultiPartFormRequest *)request];
                     }];
        
        // File and folder moving
        [self addHandlerForMethod:@"POST"
                             path:@"/move"
                     requestClass:[GCDWebServerURLEncodedFormRequest class]
                     processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                         return [server moveItem:(GCDWebServerURLEncodedFormRequest *)request];
                     }];
        
        // File and folder deletion
        [self addHandlerForMethod:@"DELETE"
                             path:@"/files"
                     requestClass:[GCDWebServerURLEncodedFormRequest class]
                     processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                         return [server deleteItem:(GCDWebServerURLEncodedFormRequest *)request];
                     }];
        
        // Directory creation
        [self addHandlerForMethod:@"POST"
                             path:@"/create"
                     requestClass:[GCDWebServerURLEncodedFormRequest class]
                     processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
                         return [server createDirectory:(GCDWebServerURLEncodedFormRequest *)request];
                     }];
        
        [self.class setLogLevel:4];
    }
    return self;
}

@end


@implementation GCDWebUploader (Methods)

// Must match implementation in GCDWebDAVServer
- (BOOL)_checkSandboxedPath:(NSString *)path {
    return [[path stringByStandardizingPath] hasPrefix:_uploadDirectory];
}

- (BOOL)_checkFileExtension:(NSString *)fileName {
    if (_allowedExtensions && ![_allowedExtensions containsObject:[[fileName pathExtension] lowercaseString]]) {
        return NO;
    }
    return YES;
}

- (NSString *)_uniquePathForPath:(NSString *)path {
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSString *directory = [path stringByDeletingLastPathComponent];
        NSString *file = [path lastPathComponent];
        NSString *base = [file stringByDeletingPathExtension];
        NSString *extension = [file pathExtension];
        int retries = 0;
        do {
            if (extension.length) {
                path = [directory stringByAppendingPathComponent:[[base stringByAppendingFormat:@" (%i)", ++retries] stringByAppendingPathExtension:extension]];
            } else {
                path = [directory stringByAppendingPathComponent:[base stringByAppendingFormat:@" (%i)", ++retries]];
            }
        } while ([[NSFileManager defaultManager] fileExistsAtPath:path]);
    }
    return path;
}

- (GCDWebServerResponse *)listDirectory:(GCDWebServerRequest *)request {
    NSString *absolutePath = _uploadDirectory.copy;
    NSString *directoryName = [absolutePath lastPathComponent];
    
    BOOL isDirectory = NO;
    if (![self _checkSandboxedPath:absolutePath] || ![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", directoryName];
    }
    if (!isDirectory) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"\"%@\" is not a directory", directoryName];
    }
    
    if (!_allowHidden && [directoryName hasPrefix:@"."]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Listing directory name \"%@\" is not allowed", directoryName];
    }
    
    NSArray *array = [self.delegate loadFileList] ?: @[];
    
    return [GCDWebServerDataResponse responseWithJSONObject:array];
}

- (GCDWebServerResponse *)downloadFile:(GCDWebServerRequest *)request {
    NSString *relativePath = [[request query] objectForKey:@"path"];
    NSString *absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
    BOOL isDirectory = NO;
    if (![self _checkSandboxedPath:absolutePath] || ![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    if (isDirectory) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"\"%@\" is a directory", relativePath];
    }
    
    NSString *fileName = [absolutePath lastPathComponent];
    if (([fileName hasPrefix:@"."] && !_allowHidden) || ![self _checkFileExtension:fileName]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Downlading file name \"%@\" is not allowed", fileName];
    }
    
    if ([self.delegate respondsToSelector:@selector(webUploader:didDownloadFileAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate webUploader:self didDownloadFileAtPath:absolutePath];
        });
    }
    return [GCDWebServerFileResponse responseWithFile:absolutePath isAttachment:YES];
}

- (GCDWebServerResponse *)uploadFile:(GCDWebServerMultiPartFormRequest *)request {
    NSRange range = [[request.headers objectForKey:@"Accept"] rangeOfString:@"application/json" options:NSCaseInsensitiveSearch];
    NSString *contentType = (range.location != NSNotFound ? @"application/json" : @"text/plain; charset=utf-8"); // Required when using iFrame transport (see https://github.com/blueimp/jQuery-File-Upload/wiki/Setup)
    
    GCDWebServerMultiPartFile *file = [request firstFileForControlName:@"newfile"];
    if ((!_allowHidden && [file.fileName hasPrefix:@"."]) || ![self _checkFileExtension:file.fileName]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Uploaded file name \"%@\" is not allowed", file.fileName];
    }
    NSString *relativePath = [[request firstArgumentForControlName:@"path"] string];
    NSString *absolutePath = [self _uniquePathForPath:[[_uploadDirectory stringByAppendingPathComponent:relativePath] stringByAppendingPathComponent:file.fileName]];
    if (![self _checkSandboxedPath:absolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    
    if (![self shouldUploadFileAtPath:absolutePath withTemporaryFile:file.temporaryPath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Uploading file \"%@\" to \"%@\" is not permitted", file.fileName, relativePath];
    }
    
    NSError *error = nil;
    if (![[NSFileManager defaultManager] moveItemAtPath:file.temporaryPath toPath:absolutePath error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed moving uploaded file to \"%@\"", relativePath];
    }
    
    if ([self.delegate respondsToSelector:@selector(webUploader:didUploadFileAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate webUploader:self didUploadFileAtPath:absolutePath];
        });
    }
    return [GCDWebServerDataResponse responseWithJSONObject:@{} contentType:contentType];
}

- (GCDWebServerResponse *)moveItem:(GCDWebServerURLEncodedFormRequest *)request {
    NSString *oldRelativePath = [request.arguments objectForKey:@"oldPath"];
    NSString *oldAbsolutePath = [_uploadDirectory stringByAppendingPathComponent:oldRelativePath];
    BOOL isDirectory = NO;
    if (![self _checkSandboxedPath:oldAbsolutePath] || ![[NSFileManager defaultManager] fileExistsAtPath:oldAbsolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", oldRelativePath];
    }
    
    NSString *newRelativePath = [request.arguments objectForKey:@"newPath"];
    NSString *newAbsolutePath = [self _uniquePathForPath:[_uploadDirectory stringByAppendingPathComponent:newRelativePath]];
    if (![self _checkSandboxedPath:newAbsolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", newRelativePath];
    }
    
    NSString *itemName = [newAbsolutePath lastPathComponent];
    if ((!_allowHidden && [itemName hasPrefix:@"."]) || (!isDirectory && ![self _checkFileExtension:itemName])) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Moving to item name \"%@\" is not allowed", itemName];
    }
    
    if (![self shouldMoveItemFromPath:oldAbsolutePath toPath:newAbsolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Moving \"%@\" to \"%@\" is not permitted", oldRelativePath, newRelativePath];
    }
    
    NSError *error = nil;
    if (![[NSFileManager defaultManager] moveItemAtPath:oldAbsolutePath toPath:newAbsolutePath error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed moving \"%@\" to \"%@\"", oldRelativePath, newRelativePath];
    }
    
    if ([self.delegate respondsToSelector:@selector(webUploader:didMoveItemFromPath:toPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate webUploader:self didMoveItemFromPath:oldAbsolutePath toPath:newAbsolutePath];
        });
    }
    return [GCDWebServerDataResponse responseWithJSONObject:@{}];
}

- (GCDWebServerResponse *)deleteItem:(GCDWebServerURLEncodedFormRequest *)request {
    NSString *relativePath = [request.arguments objectForKey:@"path"];
    NSString *absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
    BOOL isDirectory = NO;
    if (![self _checkSandboxedPath:absolutePath] || ![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    
    NSString *itemName = [absolutePath lastPathComponent];
    if (([itemName hasPrefix:@"."] && !_allowHidden) || (!isDirectory && ![self _checkFileExtension:itemName])) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Deleting item name \"%@\" is not allowed", itemName];
    }
    
    if (![self shouldDeleteItemAtPath:absolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Deleting \"%@\" is not permitted", relativePath];
    }
    
    //    NSError *error = nil;
    //    if (![[NSFileManager defaultManager] removeItemAtPath:absolutePath error:&error]) {
    //        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed deleting \"%@\"", relativePath];
    //    }
    
    if ([self.delegate respondsToSelector:@selector(webUploader:didDeleteItemAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate webUploader:self didDeleteItemAtPath:absolutePath];
        });
    }
    return [GCDWebServerDataResponse responseWithJSONObject:@{}];
}

- (GCDWebServerResponse *)createDirectory:(GCDWebServerURLEncodedFormRequest *)request {
    NSString *relativePath = [request.arguments objectForKey:@"path"];
    NSString *absolutePath = [self _uniquePathForPath:[_uploadDirectory stringByAppendingPathComponent:relativePath]];
    if (![self _checkSandboxedPath:absolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
    }
    
    NSString *directoryName = [absolutePath lastPathComponent];
    if (!_allowHidden && [directoryName hasPrefix:@"."]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Creating directory name \"%@\" is not allowed", directoryName];
    }
    
    if (![self shouldCreateDirectoryAtPath:absolutePath]) {
        return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Creating directory \"%@\" is not permitted", relativePath];
    }
    
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:absolutePath withIntermediateDirectories:NO attributes:nil error:&error]) {
        return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed creating directory \"%@\"", relativePath];
    }
    
    if ([self.delegate respondsToSelector:@selector(webUploader:didCreateDirectoryAtPath:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate webUploader:self didCreateDirectoryAtPath:absolutePath];
        });
    }
    return [GCDWebServerDataResponse responseWithJSONObject:@{}];
}

@end


@implementation GCDWebUploader (Subclassing)

- (BOOL)shouldUploadFileAtPath:(NSString *)path withTemporaryFile:(NSString *)tempPath {
    return YES;
}

- (BOOL)shouldMoveItemFromPath:(NSString *)fromPath toPath:(NSString *)toPath {
    return YES;
}

- (BOOL)shouldDeleteItemAtPath:(NSString *)path {
    return YES;
}

- (BOOL)shouldCreateDirectoryAtPath:(NSString *)path {
    return YES;
}

@end
