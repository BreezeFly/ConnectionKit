//
//  SVContentPlugIn.m
//  Sandvox
//
//  Created by Mike on 20/10/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "SVContentPlugIn.h"

#import "KTAbstractHTMLPlugin.h"
#import "SVContentObject.h"
#import "SVHTMLTemplateParser.h"


@implementation SVContentPlugIn

- (NSString *)HTMLString;
{
    NSString *result = [NSString stringWithFormat:
                        @"<span id=\"%@\">%@</span>",
                        [self elementID],
                        [self innerHTMLString]];
    return result;
}

- (NSString *)elementID
{
    NSString *result = [NSString stringWithFormat:@"%p", self];
    return result;
}

- (NSString *)innerHTMLString;
{
    // Parse our built-in template
    NSString *template = [[[self delegateOwner] plugin] templateHTMLAsString];
	SVHTMLTemplateParser *parser = [[SVHTMLTemplateParser alloc] initWithTemplate:template
                                                                        component:[self delegateOwner]];
    
    NSString *result = [parser parseTemplate];
    [parser release];
    
    return result;
}

- (NSBundle *)bundle { return [NSBundle bundleForClass:[self class]]; }

#pragma mark Legacy

- (void)awakeFromBundleAsNewlyCreatedObject:(BOOL)isNewlyCreatedObject { }

@synthesize delegateOwner = _delegateOwner;

- (KTMediaManager *)mediaManager { return [[self delegateOwner] mediaManager]; }

@end
