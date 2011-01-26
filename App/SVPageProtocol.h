//
//  SVPageProtocol.h
//  Sandvox
//
//  Created by Mike on 02/01/2010.
//  Copyright 2010-2011 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SVPlugIn.h"

typedef enum { kTruncateNone, kTruncateCharacters, kTruncateWords, kTruncateSentences, kTruncateParagraphs } SVTruncationType;

@protocol SVPage <NSObject>

#pragma mark Content
- (NSString *)title;
- (BOOL)writeSummary:(id <SVPlugInContext>)context includeLargeMedia:(BOOL)includeLargeMedia truncation:(NSUInteger)maxCount;


#pragma mark Properties
- (NSString *)language;             // KVO-compliant
- (NSString *)timestampDescription; // nil if page does't have/want timestamp


#pragma mark Children

// Most SVPage methods aren't KVO-compliant. Instead, observe all of -automaticRearrangementKeyPaths.
@property(nonatomic, readonly) BOOL isCollection;   // or is it enough to test if childPages is non-nil?
- (NSArray *)childPages;
- (id <SVPage>)parentPage;
- (id <SVPage>)rootPage;

- (NSArray *)archivePages;


#pragma mark Navigation

@property(nonatomic, readonly) NSURL *feedURL;  // KVO-compliant

- (BOOL)shouldIncludeInIndexes;
- (BOOL)shouldIncludeInSiteMaps;


@end
