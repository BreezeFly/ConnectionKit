// 
//  SVImage.m
//  Sandvox
//
//  Created by Mike on 27/01/2010.
//  Copyright 2010 Karelia Software. All rights reserved.
//

#import "SVImage.h"

#import "SVApplicationController.h"
#import "SVImageDOMController.h"
#import "SVLink.h"
#import "SVMediaGraphicInspector.h"
#import "SVMediaRecord.h"
#import "SVSiteItem.h"
#import "SVTextAttachment.h"
#import "SVWebEditorHTMLContext.h"
#import "KSWebLocation.h"

#import "NSManagedObject+KTExtensions.h"

#import "NSBitmapImageRep+Karelia.h"
#import "NSError+Karelia.h"
#import "NSString+Karelia.h"
#import "NSURL+Karelia.h"
#import "KSThreadProxy.h"


@interface SVImage ()
@end


#pragma mark -


@implementation SVImage 

+ (NSArray *)plugInKeys;
{
    return [[super plugInKeys] arrayByAddingObjectsFromArray:[NSArray arrayWithObjects:
                                                              @"alternateText",
                                                              @"link",
                                                              nil]];
}

- (void)dealloc;
{
    [_altText release];
    
    [super dealloc];
}

#pragma mark Metrics

- (void)XmakeOriginalSize;
{
    if ([self media] || ![self externalSourceURL])
    {
        [super makeOriginalSize];
    }
    else    // external images should go back to auto. #92571
    {
        [self setWidth:0];
        [self setHeight:0];
    }
}

+ (NSOperationQueue*) sharedDimensionCheckQueue;
{
	static NSOperationQueue *sSharedDimensionCheckQueue = nil;
	@synchronized(self)
	{
		if (sSharedDimensionCheckQueue == nil)
		{
			sSharedDimensionCheckQueue = [[NSOperationQueue alloc] init];
		}
	}
	return sSharedDimensionCheckQueue;
}

// Called back on main thread 
- (void)gotSize:(NSSize)aSize;
{
	OBASSERT([NSThread isMainThread]);

	if (aSize.width && aSize.height)
	{
		[self setNaturalWidth:[NSNumber numberWithFloat:aSize.width] height:[NSNumber numberWithFloat:aSize.height]];
	}
}

- (void)getDimensionsFromURL:(NSURL *)aURL		// CALLED FROM OPERATION
{
	OBASSERT(![NSThread isMainThread]);
	OBPRECONDITION(aURL);

	NSSize theSize = NSZeroSize;
	
	CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)aURL, NULL);
	if (source)
	{
		NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
								 [NSNumber numberWithBool:NO],kCGImageSourceShouldCache,
								 nil];
		
		CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(source,  0, (CFDictionaryRef)options );
		
		if (props)
		{
			NSNumber *height = [((NSDictionary *)props) objectForKey:((NSString *)kCGImagePropertyPixelHeight)];
			NSNumber *width  = [((NSDictionary *)props) objectForKey:((NSString *)kCGImagePropertyPixelWidth)];
			theSize = NSMakeSize(width.intValue, height.intValue);
			
			CFRelease(props);
		}
		CFRelease(source);
	}
	
	[[self ks_proxyOnThread:nil waitUntilDone:NO] gotSize:theSize];
}

- (void)getDimensionsFromRemoteImage;
{
	NSURL *sourceURL = [self externalSourceURL];
	if (sourceURL)
	{
		// Use imageIO to check the dimensions, on a background thread.
	
		NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithTarget:self
																				selector:@selector(getDimensionsFromURL:)
																				  object:sourceURL];
		[[[self class] sharedDimensionCheckQueue] addOperation:operation];
        [operation release];
	}
}

#pragma mark Media

- (void)didSetSource;
{
    [super didSetSource];
    
    // Adjust file type if not valid
    if (![self validateTypeToPublish:[[self container] typeToPublish]])
    {
        [[self container] setTypeToPublish:(NSString *)kUTTypeJPEG];
    }
    
    // External images become auto sized
    if (![self media] && [self externalSourceURL])
    {
        [[self container] setConstrainProportions:NO];
        [self setWidth:0];
        [self setHeight:0];
		
		[self getDimensionsFromRemoteImage];
    }
}

+ (NSArray *)allowedFileTypes
{
	return [NSBitmapImageRep imageTypes];
}

- (BOOL)validateTypeToPublish:(NSString *)type;
{
    BOOL result = ([type isEqualToString:(NSString *)kUTTypeJPEG] ||
                   [type isEqualToString:(NSString *)kUTTypePNG] ||
                   [type isEqualToString:(NSString *)kUTTypeGIF]);
    
    return result;
}

#pragma mark Alt Text

@synthesize alternateText = _altText;

#pragma mark Placement

- (BOOL)shouldWriteHTMLInline;
{
    BOOL result = [super shouldWriteHTMLInline];
    
    // Images become inline once you turn off all additional stuff like title & caption
    if (![[self container] isPagelet])
    {
        SVTextAttachment *attachment = [[self container] textAttachment];
        if (![[attachment causesWrap] boolValue])
        {
            result = YES;
        }
        else
        {
            SVGraphicWrap wrap = [[attachment wrap] intValue];
            result = (wrap == SVGraphicWrapRight ||
                      wrap == SVGraphicWrapLeft ||
                      wrap == SVGraphicWrapNone);
        }
    }
    
    return result;
}

- (BOOL)canWriteHTMLInline; { return YES; }

+ (NSSet *)keyPathsForValuesAffectingIsPagelet;
{
    return [NSSet setWithObjects:
            @"placement",
            @"showsTitle",
            @"showsIntroduction",
            @"showsCaption", nil];
}

#pragma mark Link

@synthesize link = _link;

- (id)serializedValueForKey:(NSString *)key;
{
    if ([key isEqualToString:@"link"])
    {
        SVLink *link = [self link];
        // If the link is to a page, actually archive a different link that references the ID-only
        if ([link page])
        {
            link = [SVLink linkWithURLString:[link URLString] openInNewWindow:[link openInNewWindow]];
        }
        
        NSData *data = (link ? [NSKeyedArchiver archivedDataWithRootObject:link] : nil);
        return data;
    }
    else
    {
        return [super serializedValueForKey:key];
    }
}

- (void)setSerializedValue:(id)serializedValue forKey:(NSString *)key;
{
    if ([key isEqualToString:@"link"])
    {
        SVLink *result = nil;
        if (serializedValue)
        {
            result = [NSKeyedUnarchiver unarchiveObjectWithData:serializedValue];
            
            SVSiteItem *page = [SVSiteItem siteItemForPreviewPath:[result URLString]
                                           inManagedObjectContext:[[self container] managedObjectContext]];
            
            if (page) result = [SVLink linkWithSiteItem:page openInNewWindow:[result openInNewWindow]];
        }
        
        [self setLink:result];
    }
    else
    {
        [super setSerializedValue:serializedValue forKey:key];
    }
}

#pragma mark Publishing

- (NSBitmapImageFileType)storageType;
{
    NSBitmapImageFileType result = [NSBitmapImageRep typeForUTI:[[self container] typeToPublish]];
    return result;
}
- (void) setStorageType:(NSBitmapImageFileType)storageType;
{
    [[self container] setTypeToPublish:[NSBitmapImageRep ks_typeForBitmapImageFileType:storageType]];
}
+ (NSSet *)keyPathsForValuesAffectingStorageType;
{
    return [NSSet setWithObject:@"typeToPublish"];
}

@dynamic compressionFactor;

#pragma mark HTML

- (void)writeHTML:(SVHTMLContext *)context
{
    // Link
    BOOL isPagelet = [[self container] isPagelet];
    if (isPagelet && [self link])
    {
        [context startAnchorElementWithHref:[[self link] URLString] title:nil target:nil rel:nil];
    }
    
    
    // Actually write the image
    NSString *alt = [self alternateText];
    if (!alt) alt = @"";
    
    if ([self shouldWriteHTMLInline]) [[self container] buildClassName:context];
    
    [context buildAttributesForElement:@"img" bindSizeToObject:self DOMControllerClass:[SVImageDOMController class]  sizeDelta:NSZeroSize];
    
    SVMediaRecord *media = [self media];
    if (media)
    {
        [context writeImageWithSourceMedia:media
                                       alt:alt
                                     width:self.container.width
                                    height:self.container.height
                                      type:[[self container] typeToPublish]
                         preferredFilename:nil];
    }
    else
    {
        NSURL *URL = [self externalSourceURL];
        
        [context writeImageWithSrc:(URL ? [context relativeURLStringOfURL:URL] : @"")
                               alt:alt
                             width:self.container.width
                            height:self.container.height];
    }
    
    [context addDependencyOnObject:self keyPath:@"media"];
    
    
    if ([[self container] isPagelet] && [self link]) [context endElement];
}

- (BOOL)shouldPublishEditingElementID; { return NO; }

#pragma mark Inspector

+ (SVInspectorViewController *)makeInspectorViewController;
{
    SVInspectorViewController *result = [[[SVMediaGraphicInspector alloc]
                                          initWithNibName:@"SVImage" bundle:nil]
                                         autorelease];
    
    return result;
}

#pragma mark Thumbnail

- (NSString *)imageRepresentationType;
{
    return ([[self thumbnailMedia] mediaData] ?
            IKImageBrowserNSDataRepresentationType :
            IKImageBrowserNSURLRepresentationType);
}

@end
