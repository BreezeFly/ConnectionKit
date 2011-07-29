//
//  SVGraphicContainerDOMController.m
//  Sandvox
//
//  Created by Mike on 23/11/2010.
//  Copyright 2010-2011 Karelia Software. All rights reserved.
//

#import "SVGraphicContainerDOMController.h"

#import "SVCalloutDOMController.h"
#import "SVContentDOMController.h"
#import "SVMediaRecord.h"
#import "KTPage.h"
#import "SVPasteboardItemInternal.h"
#import "SVRichTextDOMController.h"
#import "SVTextAttachment.h"
#import "SVWebEditorHTMLContext.h"
#import "SVWebEditorViewController.h"
#import "WebViewEditingHelperClasses.h"

#import "KSGeometry.h"

#import "DOMNode+Karelia.h"


@interface SVGraphicPlaceholderDOMController : SVGraphicContainerDOMController
@end


#pragma mark -


@implementation SVGraphicContainerDOMController

- (void)dealloc;
{
    [self setBodyHTMLElement:nil];
    OBPOSTCONDITION(!_bodyElement);
    
    [_offscreenWebViewController setDelegate:nil];
    [_offscreenWebViewController release];  // dealloc-ing mid-update
    [_offscreenContext release];
    
    [self setRepresentedObject:nil];
    
    [super dealloc];
}

#pragma mark Factory

+ (SVGraphicContainerDOMController *)graphicPlaceholderDOMController;
{
    SVGraphicContainerDOMController *result = [[[SVGraphicPlaceholderDOMController alloc] init] autorelease];
    return result;
}

#pragma mark Content

- (void)setRepresentedObject:(id)object
{
    [super setRepresentedObject:object];
}

#pragma mark DOM

- (void)setHTMLElement:(DOMHTMLElement *)element;
{
    // Is this a change due to being orphaned while editing? If so, pass down to image controller too. #83312
    for (WEKWebEditorItem *anItem in [self childWebEditorItems])
    {
        if ([self isHTMLElementLoaded] && ([self HTMLElement] == [anItem HTMLElement]))
        {
            [anItem setHTMLElement:element];
        }
    }
    
    
    [super setHTMLElement:element];
}

@synthesize bodyHTMLElement = _bodyElement;

- (DOMElement *)graphicDOMElement;
{
    id result = [[[self HTMLElement] getElementsByClassName:@"graphic"] item:0];
    return result;
}

- (void)loadHTMLElementFromDocument:(DOMDocument *)document;
{
    [super loadHTMLElementFromDocument:document];
    
    // Locate body element too
    SVGraphic *graphic = [[self representedObject] graphic];
    if ([self isHTMLElementLoaded])
    {
        if ([graphic isPagelet])
        {
            DOMNodeList *elements = [[self HTMLElement] getElementsByClassName:@"pagelet-body"];
            [self setBodyHTMLElement:(DOMHTMLElement *)[elements item:0]];
        }
        else
        {
            if ([self isHTMLElementLoaded]) [self setBodyHTMLElement:[self HTMLElement]];
        }
    }
}

- (void)loadPlaceholderDOMElementInDocument:(DOMDocument *)document;
{
    DOMElement *element = [document createElement:@"DIV"];
    [[element style] setDisplay:@"none"];
    [self setHTMLElement:(DOMHTMLElement *)element];
}

#pragma mark Updating

- (void)updateWithDOMNode:(DOMNode *)node items:(NSArray *)items;
{
    // Swap in updated node. Then get the Web Editor to hook new descendant controllers up to the new nodes
    [[[self HTMLElement] parentNode] replaceChild:node oldChild:[self HTMLElement]];
    //[self setHTMLElement:nil];  // so Web Editor will endeavour to hook us up again
    
    
    // Hook up new DOM Controllers
    for (WEKWebEditorItem *anItem in items)
    {
        [anItem setAncestorNode:[self ancestorNode] recursive:YES];
    }
    
    
    
    SVWebEditorViewController *viewController = [self webEditorViewController];
    [viewController willUpdate];    // wrap the replacement like this so doesn't think update finished too early
    {
        [self didUpdateWithSelector:@selector(update)];
        [[self retain] autorelease];    // replacement is likely to deallocate us
        [[self parentWebEditorItem] replaceChildWebEditorItem:self withItems:items];
    }
    [viewController didUpdate];
}

- (void)update;
{
    // Tear down dependencies etc.
    [self stopObservingDependencies];
    //[self setChildWebEditorItems:nil];
    
    
    // Setup the context
    KSStringWriter *html = [[KSStringWriter alloc] init];
    
    SVWebEditorHTMLContext *context = [[[SVWebEditorHTMLContext class] alloc]
                                       initWithOutputWriter:html inheritFromContext:[self HTMLContext]];
    
    [context writeJQueryImport];    // for any plug-ins that might depend on it
    [context writeExtraHeaders];
    
    //[[context rootDOMController] setWebEditorViewController:[self webEditorViewController]];
    
    
    // Write HTML
    id object = [self representedObject];
    id <SVComponent> container = [[self graphicContainerDOMController] representedObject];   // rarely nil, but sometimes is. #116816
    
    if (container) [context beginGraphicContainer:container];
    [context writeGraphic:[object graphic]];
    if (container) [context endGraphicContainer];
    
    
    // Copy out controllers
    [_offscreenContext release];
    _offscreenContext = [context retain];
    
    
    // Copy top-level dependencies across to parent. #79396
    [context flush];    // you never know!
    for (KSObjectKeyPathPair *aDependency in [[context rootElement] dependencies])
    {
        [(SVDOMController *)[self parentWebEditorItem] addDependency:aDependency];
    }
    
    
    // Copy across data resources
    WebDataSource *dataSource = [[[[self webEditor] webView] mainFrame] dataSource];
    for (SVMedia *media in [context media])
    {
        if ([media webResource])
        {
            [dataSource addSubresource:[media webResource]];
        }
    }
    
    
    // Bring end body code into the html
    [context writeEndBodyString];
    [context close];
    [context release];
    
    
    DOMHTMLDocument *doc = (DOMHTMLDocument *)[[self HTMLElement] ownerDocument];
    DOMDocumentFragment *fragment = [doc createDocumentFragmentWithMarkupString:[html string] baseURL:nil];
    
    if (fragment)
    {
        SVContentDOMController *rootController = [[SVContentDOMController alloc]
                                                  initWithWebEditorHTMLContext:_offscreenContext
                                                  node:fragment];
        DOMElement *anElement = [fragment firstChildOfClass:[DOMElement class]];
        while (anElement)
        {
            if ([[anElement getElementsByTagName:@"SCRIPT"] length]) break; // deliberately ignoring top-level scripts
            
            NSString *ID = [[[rootController childWebEditorItems] objectAtIndex:0] elementIdName];
            if ([ID isEqualToString:[anElement getAttribute:@"id"]])
            {
                // Search for any following scripts
                if ([anElement nextSiblingOfClass:[DOMHTMLScriptElement class]]) break;
                
                // No scripts, so can update directly
                [self updateWithDOMNode:anElement items:[rootController childWebEditorItems]];
                
                [rootController release];
                [_offscreenContext release]; _offscreenContext = nil;
                return;
            }
            
            anElement = [anElement nextSiblingOfClass:[DOMElement class]];
        }
        
        [rootController release];
    }
    
    
    // Start loading DOM objects from HTML
    if (_offscreenWebViewController)
    {
        // Need to restart loading. Do so by pretending we already finished
        [self didUpdateWithSelector:_cmd];
    }
    else
    {
        _offscreenWebViewController = [[SVOffscreenWebViewController alloc] init];
        [_offscreenWebViewController setDelegate:self];
    }
    
    [_offscreenWebViewController loadHTMLFragment:[html string]];
    [html release];
}

+ (DOMHTMLHeadElement *)headOfDocument:(DOMDocument *)document;
{
    if ([document respondsToSelector:@selector(head)])
    {
        return [document performSelector:@selector(head)];
    }
    else
    {
        DOMNodeList *nodes = [document getElementsByTagName:@"HEAD"];
        return (DOMHTMLHeadElement *)[nodes item:0];
    }
}

- (void)disableScriptsInNode:(DOMNode *)fragment;
{
    // I have to turn off the script nodes from actually executing
	DOMNodeIterator *it = [[fragment ownerDocument] createNodeIterator:fragment whatToShow:DOM_SHOW_ELEMENT filter:[ScriptNodeFilter sharedFilter] expandEntityReferences:NO];
	DOMHTMLScriptElement *subNode;
    
	while ((subNode = (DOMHTMLScriptElement *)[it nextNode]))
	{
		[subNode setText:@""];		/// HACKS -- clear out the <script> tags so that scripts are not executed AGAIN
		[subNode setSrc:@""];
		[subNode setType:@""];
	}
}

- (void)stopUpdate;
{
    [_offscreenWebViewController setDelegate:nil];
    [_offscreenWebViewController release]; _offscreenWebViewController = nil;
    [_offscreenContext release]; _offscreenContext = nil;
}

- (void)offscreenWebViewController:(SVOffscreenWebViewController *)controller
                       didLoadBody:(DOMHTMLElement *)loadedBody;
{
    // Pull the nodes across to the Web Editor
    DOMDocument *document = [[self HTMLElement] ownerDocument];
    DOMDocumentFragment *fragment = [document createDocumentFragment];
    DOMDocumentFragment *bodyFragment = [document createDocumentFragment];
    DOMNodeList *children = [loadedBody childNodes];
    
    BOOL importedContent = NO;
    for (int i = 0; i < [children length]; i++)
    {
        DOMNode *node = [children item:i];
        
        // Try adopting the node, then fallback to import, as described in http://www.w3.org/TR/DOM-Level-3-Core/core.html#Document3-adoptNode
        DOMNode *imported = [document adoptNode:node];
        if (!imported)
        {
            // TODO:
            // As noted at http://www.w3.org/TR/DOM-Level-3-Core/core.html#Core-Document-importNode this could raise an exception, which we should probably catch and handle in some fashion
            imported = [document importNode:node deep:YES];
        }
        
        // Is this supposed to be inserted at top of doc?
        if (importedContent)
        {
            [fragment appendChild:imported];
        }
        else
        {
            if ([imported isKindOfClass:[DOMElement class]])
            {
                DOMHTMLElement *element = (DOMHTMLElement *)imported;
                NSString *ID = [element idName];
                if (ID)
                {
                    [fragment appendChild:imported];
                    importedContent = YES;
                    continue;
                }
            }
            
            [bodyFragment appendChild:imported];
        }
    }
    
    
    
    // I have to turn off the script nodes from actually executing
	[self disableScriptsInNode:fragment];
    [self disableScriptsInNode:bodyFragment];
    
    
    // Import headers too
    DOMDocument *offscreenDoc = [loadedBody ownerDocument];
    DOMNodeList *headNodes = [[[self class] headOfDocument:offscreenDoc] childNodes];
    DOMHTMLElement *head = [[self class] headOfDocument:document];
    
    for (int i = 0; i < [headNodes length]; i++)
    {
        DOMNode *aNode = [headNodes item:i];
        aNode = [document importNode:aNode deep:YES];
        [head appendChild:aNode];
    }
    
    
    // Are we missing a callout?
    SVGraphic *graphic = (SVGraphic *)[[self representedObject] graphic];
    if ([graphic isCallout] && ![self calloutDOMController])
    {
        // Create a callout stack where we are know
        SVCalloutDOMController *calloutController = [[SVCalloutDOMController alloc] initWithHTMLDocument:(DOMHTMLDocument *)document];
        [calloutController loadHTMLElement];
        
        [[[self HTMLElement] parentNode] replaceChild:[calloutController HTMLElement]
                                             oldChild:[self HTMLElement]];
        
        // Then move ourself into the callout
        [[calloutController calloutContentElement] appendChild:[self HTMLElement]];
        
        [self retain];
        [[self parentWebEditorItem] replaceChildWebEditorItem:self with:calloutController];
        [calloutController addChildWebEditorItem:self];
        [calloutController release];
        [self release];
    }
    
    
    // Update
    SVContentDOMController *rootController = [[SVContentDOMController alloc]
                                              initWithWebEditorHTMLContext:_offscreenContext
                                              node:fragment];
    
    [self updateWithDOMNode:fragment items:[rootController childWebEditorItems]];
    [rootController release];
    
    
    DOMNode *body = [(DOMHTMLDocument *)document body];
    [body insertBefore:bodyFragment refChild:[body firstChild]];
    
    
    
    // Teardown
    [self stopUpdate];
}

- (void)updateWrap;
{
    SVGraphic *graphic = [[self representedObject] graphic];
    
    
    // Some wrap changes actually need a full update. #94915
    BOOL writeInline = [graphic shouldWriteHTMLInline];
    NSString *oldTag = [[self HTMLElement] tagName];
    
    if ((writeInline && ![oldTag isEqualToString:@"IMG"]) ||
        (!writeInline && ![oldTag isEqualToString:@"DIV"]))
    {
        [self update];
        return;
    }
    
    
    // Will need redraw of some kind, particularly if selected
    [self setNeedsDisplay];
    
    // Update class name to get new wrap
    SVHTMLContext *context = [[SVHTMLContext alloc] initWithOutputWriter:nil];
    [graphic buildClassName:context includeWrap:YES];
    
    NSString *className = [[[context currentAttributes] attributesAsDictionary] objectForKey:@"class"];
    DOMHTMLElement *element = [self HTMLElement];
    [element setClassName:className];
    
    [context release];
    
    
    [self didUpdateWithSelector:_cmd];
}

- (void)setNeedsUpdate;
{
    id object = [self representedObject];
    if ([object respondsToSelector:@selector(requiresPageLoad)] && [object requiresPageLoad])
    {
        [[self webEditorViewController] setNeedsUpdate];
    }
    else
    {
        [super setNeedsUpdate];
    }
}

- (void)itemWillMoveToWebEditor:(WEKWebEditorView *)newWebEditor;
{
    [super itemWillMoveToWebEditor:newWebEditor];
    
    if (_offscreenWebViewController)
    {
        // If the update finishes while we're away from a web editor, there's no way to tell it so. So pretend the update has finished when removed. Likewise, pretend the update has started if added back to the editor. #131984
        if (newWebEditor)
        {
            [[newWebEditor delegate] performSelector:@selector(willUpdate)];
        }
        else
        {
            //[self stopUpdate];
            [self didUpdateWithSelector:@selector(update)];
        }
    }
}

#pragma mark Dependencies

- (void)dependenciesTracker:(KSDependenciesTracker *)tracker didObserveChange:(NSDictionary *)change forDependency:(KSObjectKeyPathPair *)dependency;
{
    // Special case where we don't want complete update
    if ([[dependency keyPath] isEqualToString:@"textAttachment.wrap"])
    {
        [self setNeedsUpdateWithSelector:@selector(updateWrap)];
    }
    else
    {
        [super dependenciesTracker:tracker didObserveChange:change forDependency:dependency];
    }
}

#pragma mark Selection & Editing

- (WEKWebEditorItem *)hitTestDOMNode:(DOMNode *)node;
{
    OBPRECONDITION(node);
    
    WEKWebEditorItem *result = nil;
    
    
    if ([self isSelectable])    // think we don't need this code branch any more
    {
        // Standard logic mostly works, but we want to ignore anything outside the graphic, instead of the HTML element
        DOMElement *testElement = [self graphicDOMElement];
        if (!testElement) testElement = [self HTMLElement];
        
        if ([node ks_isDescendantOfElement:testElement])
        {
            NSArray *children = [self childWebEditorItems];
            
            // Search for a descendant
            // Body DOM Controller will take care of looking for a single selectable child for us
            for (WEKWebEditorItem *anItem in children)
            {
                result = [anItem hitTestDOMNode:node];
                if (result) break;
            }
            
            
            if (!result && [children count] > 1) result = self;
        }
    }
    else
    {
        result = [super hitTestDOMNode:node];
    }
    
    return result;
}

- (DOMElement *)selectableDOMElement;
{
    return nil;
    
    
    DOMElement *result = [self graphicDOMElement];
    if (!result) result = (id)[[[self HTMLElement] getElementsByClassName:@"pagelet-body"] item:0];
    ;
    
    
    // Seek out a better matching child which has no siblings. #93557
    DOMTreeWalker *walker = [[result ownerDocument] createTreeWalker:result
                                                          whatToShow:DOM_SHOW_ELEMENT
                                                              filter:nil
                                              expandEntityReferences:NO];
    
    DOMNode *aNode = [walker currentNode];
    while (aNode && ![walker nextSibling])
    {
        WEKWebEditorItem *controller = [super hitTestDOMNode:aNode];
        if (controller != self && [controller isSelectable])
        {
            result = nil;
            break;
        }
        
        aNode = [walker nextNode];
    }
    
    return result;
}

- (void)setEditing:(BOOL)editing;
{
    [super setEditing:editing];
    
    
    // Make sure we're selectable while editing
    if (editing)
    {
        [[[self HTMLElement] style] setProperty:@"-webkit-user-select"
                                          value:@"auto"
                                       priority:@""];
    }
    else
    {
        [[[self HTMLElement] style] removeProperty:@"-webkit-user-select"];
    }
}

- (NSRect)selectionFrame;
{
    DOMElement *element = [self selectableDOMElement];
    if (element)
    {
        return [element boundingBox];
    }
    else
    {
        // Union together children, but only vertically once the firsy has been found
        NSRect result = NSZeroRect;
        for (WEKWebEditorItem *anItem in [self selectableTopLevelDescendants])
        {
            if (result.size.width > 0.0f)
            {
                result = [KSGeometry KSVerticallyUnionRect:result :[anItem selectionFrame]];
            }
            else
            {
                result = NSUnionRect(result, [anItem selectionFrame]);
            }
        }
        
        return result;
    }
    
    //DOMElement *element = [self graphicDOMElement];
    if (!element) element = [self HTMLElement];
    return [element boundingBox];
}

#pragma mark Paste

- (void)paste:(id)sender;
{
    SVGraphic *graphic = [[self representedObject] graphic];
    
    if (![graphic awakeFromPasteboardItems:[[NSPasteboard generalPasteboard] sv_pasteboardItems]])
    {
        if (![[self nextResponder] tryToPerform:_cmd with:sender])
        {
            NSBeep();
        }
    }
}

#pragma mark Events

- (NSMenu *)menuForEvent:(NSEvent *)theEvent;
{
    if (![self isSelected]) return [super menuForEvent:theEvent];
    
    
    NSMenu *result = [[[NSMenu alloc] init] autorelease];
    
    [result addItemWithTitle:NSLocalizedString(@"Delete", "menu item")
                      action:@selector(delete:)
               keyEquivalent:@""];
    
    return result;
}

#pragma mark Attributed HTML

- (BOOL)writeAttributedHTML:(SVFieldEditorHTMLWriterDOMAdapator *)adaptor;
{
    SVGraphic *graphic = [[self representedObject] graphic];
    SVTextAttachment *attachment = [graphic textAttachment];
    
    
    // Is it allowed?
    if ([graphic isPagelet])
    {
        if ([adaptor importsGraphics] && [(id)adaptor allowsPagelets])
        {
            if ([[adaptor XMLWriter] openElementsCount] > 0)
            {
                return NO;
            }
        }
        else
        {
            NSLog(@"This text block does not support block graphics");
            return NO;
        }
    }
    
    
    
    
    // Go ahead and write    
    
    // Newly inserted graphics tend not to have a corresponding text attachment yet. If so, create one
    if (!attachment)
    {
        attachment = [SVTextAttachment textAttachmentWithGraphic:graphic];
        
        // Guess placement from controller hierarchy
        SVGraphicPlacement placement = ([self calloutDOMController] ?
                                        SVGraphicPlacementCallout :
                                        SVGraphicPlacementInline);
        [attachment setPlacement:[NSNumber numberWithInteger:placement]];
        
        //[attachment setWrap:[NSNumber numberWithInteger:SVGraphicWrapRightSplit]];
        [attachment setBody:[[self textDOMController] representedObject]];
    }
    
    
    // Set attachment location
    [adaptor writeTextAttachment:attachment];
    
    [[adaptor XMLWriter] flush];
    KSStringWriter *stringWriter = [adaptor valueForKeyPath:@"_output"];     // HACK!
    NSRange range = NSMakeRange([(NSString *)stringWriter length] - 1, 1);  // HACK!
    
    if (!NSEqualRanges([attachment range], range))
    {
        [attachment setRange:range];
    }
    
    
    
    
    
    return YES;
}

#pragma mark Moving

- (BOOL)moveToPosition:(CGPoint)position event:(NSEvent *)event;
{
    // See if super fancies a crack
    if ([super moveToPosition:position event:event]) return YES;
    
    
    WEKWebEditorItem <SVGraphicContainerDOMController> *dragController = [self graphicContainerDOMController];
    if ([dragController graphicContainerDOMController]) dragController = [dragController graphicContainerDOMController];
    
    [dragController moveGraphicWithDOMController:self toPosition:position event:event];
    
    
    // Starting a move turns off selection handles so needs display
    if (dragController && ![self hasRelativePosition])
    {
        [self setNeedsDisplay];
        //_moving = YES;
    }
    
    return (dragController != nil);
}

- (void)moveEnded;
{
    [super moveEnded];
    [self removeRelativePosition:YES];
}

/*  Have to re-implement because SVDOMController overrides
 */
- (CGPoint)position;
{
    NSRect rect = [self selectionFrame];
    return CGPointMake(NSMidX(rect), NSMidY(rect));
}

- (NSArray *)relativePositionDOMElements;
{
    DOMElement *result = [self graphicDOMElement];
    if (result)
    {
        DOMElement *caption = [result nextSiblingOfClass:[DOMElement class]];
        return NSARRAY(result, caption);    // caption may be nil, so go ignored
    }
    else
    {
        return [super relativePositionDOMElements];
    }
}

- (KSSelectionBorder *)newSelectionBorder;
{
    KSSelectionBorder *result = [super newSelectionBorder];
    
    // Turn off handles while moving
    if ([self hasRelativePosition]) [result setEditing:YES];
    
    return result;
}

#pragma mark Resizing

- (unsigned int)resizingMask
{
    DOMElement *element = [self graphicDOMElement];
    return (element ? [self resizingMaskForDOMElement:element] : 0);
}

- (NSSize)constrainSize:(NSSize)size handle:(SVGraphicHandle)handle snapToFit:(BOOL)snapToFit;
{
    /*  This logic is almost identical to SVPlugInDOMController, although the code here can probably be pared down to deal only with width
     */
    
    
    // If constrained proportions, apply that
    SVGraphic *graphic = [[self representedObject] graphic];
    NSNumber *ratio = [graphic constrainedProportionsRatio];
    
    if (ratio)
    {
        BOOL resizingWidth = (handle == kSVGraphicUpperLeftHandle ||
                              handle == kSVGraphicMiddleLeftHandle ||
                              handle == kSVGraphicLowerLeftHandle ||
                              handle == kSVGraphicUpperRightHandle ||
                              handle == kSVGraphicMiddleRightHandle ||
                              handle == kSVGraphicLowerRightHandle);
        
        BOOL resizingHeight = (handle == kSVGraphicUpperLeftHandle ||
                               handle == kSVGraphicUpperMiddleHandle ||
                               handle == kSVGraphicUpperRightHandle ||
                               handle == kSVGraphicLowerLeftHandle ||
                               handle == kSVGraphicLowerMiddleHandle ||
                               handle == kSVGraphicLowerRightHandle);
        
        if (resizingWidth)
        {
            if (resizingHeight)
            {
                // Go for the biggest size of the two possibilities
                CGFloat unconstrainedRatio = size.width / size.height;
                if (unconstrainedRatio < [ratio floatValue])
                {
                    size.width = size.height * [ratio floatValue];
                }
                else
                {
                    size.height = size.width / [ratio floatValue];
                }
            }
            else
            {
                size.height = size.width / [ratio floatValue];
            }
        }
        else if (resizingHeight)
        {
            size.width = size.height * [ratio floatValue];
        }
    }
    
    
    
    if (snapToFit)
    {
        CGFloat maxWidth = [self maxWidth];
        if (size.width > maxWidth)
        {
            // Keep within max width
            // Switch over to auto-sized for simple graphics
            size.width = ([graphic isExplicitlySized] ? maxWidth : 0.0f);
            if (ratio) size.height = maxWidth / [ratio floatValue];
        }
    }
    
    
    return size;
}

- (CGFloat)maxWidth;
{
    // Base limit on design rather than the DOM
    SVGraphic *graphic = [[self representedObject] graphic];
    OBASSERT(graphic);
    
    KTPage *page = [[self HTMLContext] page];
    return [graphic maxWidthOnPage:page];
}

@end


#pragma mark -


@implementation WEKWebEditorItem (SVPageletDOMController)

- (SVGraphicContainerDOMController *)enclosingGraphicDOMController;
{
    id result = [self parentWebEditorItem];
    
    if (![result isKindOfClass:[SVGraphicContainerDOMController class]])
    {
        result = [result enclosingGraphicDOMController];
    }
    
    return result;
}

@end


#pragma mark -


@implementation WEKWebEditorItem (SVGraphicContainerDOMController)

- (WEKWebEditorItem <SVGraphicContainerDOMController> *)graphicContainerDOMController;
{
    id result = [self parentWebEditorItem];
    while (result && ![result conformsToProtocol:@protocol(SVGraphicContainerDOMController)])
    {
        result = [result parentWebEditorItem];
    }
    
    return result;
}

@end


#pragma mark -


@implementation SVGraphicPlaceholderDOMController

- (void)loadHTMLElementFromDocument:(DOMHTMLDocument *)document;
{
    [self loadPlaceholderDOMElementInDocument:document];
}

@end



