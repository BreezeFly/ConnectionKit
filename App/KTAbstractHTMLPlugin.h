//
//  KTAbstractHTMLPlugin.h
//  Marvel
//
//  Created by Mike on 26/01/2008.
//  Copyright 2008-2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "KSPlugin.h"


@interface KTAbstractHTMLPlugin : KSPlugin
{
	NSImage *myIcon;
	NSString *myTemplateHTML;
}

- (NSString *)pluginName;
- (NSImage *)pluginIcon;            // derived from pluginIconName
- (NSString *)CSSClassName;
- (NSString *)templateHTMLAsString;

@end
