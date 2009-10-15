//
//  KTDocWindowController.m
//  Marvel
//
//  Created by Dan Wood on 5/4/05.
//  Copyright 2005-2009 Karelia Software. All rights reserved.
//

#import "KTDocWindowController.h"


#import "AMRollOverButton.h"
#import "Debug.h"
#import "KSSilencingConfirmSheet.h"
#import "KSTextField.h"
#import "KSNetworkNotifier.h"
#import "KT.h"
#import "KTElementPlugin+DataSourceRegistration.h"
#import "KTAbstractIndex.h"
#import "KTAppDelegate.h"
#import "KTApplication.h"
#import "KTCodeInjectionController.h"
#import "KTDesignPickerView.h"
#import "KTDocSiteOutlineController.h"
#import "KTDocument.h"
#import "KTSite.h"
#import "KTDocWebViewController.h"
#import "KTElementPlugin.h"
#import "KTHostProperties.h"
#import "KTIndexPlugin.h"
#import "KTInfoWindowController.h"
#import "KTInlineImageElement.h"
#import "KTLinkSourceView.h"
#import "KTMediaManager+Internal.h"
#import "KTMissingMediaController.h"
#import "KTPage+Internal.h"
#import "KTPagelet+Internal.h"
#import "KTPluginInspectorViewsManager.h"
#import "SVSiteOutlineViewController.h"
#import "KTToolbars.h"
#import "SVHTMLTemplateTextBlock.h"

#import "SVDesignChooserWindowController.h"

#import "NSArray+Karelia.h"
#import "NSArray+KTExtensions.h"
#import "NSBundle+Karelia.h"
#import "NSCharacterSet+Karelia.h"
#import "NSColor+Karelia.h"
#import "NSException+Karelia.h"
#import "NSManagedObjectContext+KTExtensions.h"
#import "NSSet+Karelia.h"
#import "NSObject+Karelia.h"
#import "NSOutlineView+KTExtensions.h"
#import "NSResponder+Karelia.h"
#import "NSSortDescriptor+Karelia.h"
#import "NSString+Karelia.h"
#import "NSTextView+KTExtensions.h"
#import "NSThread+Karelia.h"
#import "NSWindow+Karelia.h"

#import "NTBoxView.h"
#import "KSProgressPanel.h"

#import "Registration.h"

#import <iMediaBrowser/iMedia.h>
#import <WebKit/WebKit.h>

NSString *gInfoWindowAutoSaveName = @"Inspector TopLeft";


@interface KTDocWindowController ()

// Controller chain
- (void)removeAllChildControllers;

@end


#pragma mark -


@implementation KTDocWindowController

/*	Designated initializer.
 */
- (id)initWithWindow:(NSWindow *)window;
{
	self = [super initWithWindow:window];
	
    if (self)
    {
        _childControllers = [[NSMutableArray alloc] init];
        [self setShouldCloseDocument:YES];
    }
        
	return self;
}

- (id)init
{
	if (self = [super initWithWindowNibName:@"KTDocument"])
	{
		// do not cascade window using size in nib
		[self setShouldCascadeWindows:NO];
	}
    
    return self;
}

- (void)dealloc
{
	// Get rid of the site outline controller
	[self setSiteOutlineViewController:nil];
	
	
    // Dispose of the controller chain
    [self removeAllChildControllers];
	
    
	// stop observing
	[[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // release ivars
	[self setContextElementInformation:nil];
    [self setAddCollectionPopUpButton:nil];
    [self setAddPagePopUpButton:nil];
    [self setAddPageletPopUpButton:nil];
    [self setSelectedInlineImageElement:nil];
    [self setSelectedPagelet:nil];
    [self setToolbars:nil];
	[myMasterCodeInjectionController release];
	[myPageCodeInjectionController release];
	[myPluginInspectorViewsManager release];
	[myBuyNowButton release]; myBuyNowButton = nil;

    [super dealloc];
}

- (void)selectionDealloc
{
	[self setSelectedInlineImageElement:nil];
    [self setSelectedPagelet:nil];
}

- (void)windowDidLoad
{	
    [super windowDidLoad];
	
	
	// Now let the webview and the site outline initialize themselves.
	[self linkPanelDidLoad];
	
	
	// Early on, window-related stuff
	NSString *sizeString = [[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultDocumentWindowContentSize"];
	if ( nil != sizeString )
	{
		NSSize size = NSSizeFromString(sizeString);
		size.height = MAX(size.height, 200.0);
		size.width = MAX(size.width,800.0);
		[[self window] setContentSize:size];
	}
	
	// Toolbar
	[self setToolbars:[NSMutableDictionary dictionary]];
	[self makeDocumentToolbar];
	[self updatePopupButtonSizesSmall:[[self document] displaySmallPageIcons]];
	
	
	// Restore the window's previous frame, if available. Always do this after loading toolbar to make rect consistent
	NSRect contentRect = [[[self document] site] docWindowContentRect];
	if (!NSEqualRects(contentRect, NSZeroRect))
	{
		NSWindow *window = [self window];
		[window setFrame:[window frameRectForContentRect:contentRect] display:YES];
		// -constrainFrameRect:toScreen: will automatically stop the window going offscreen for us.
	}
	
	
	// Split View
	// Do not use autosave, we save this in document... [oSidebarSplitView restoreState:YES];
	short sourceOutlineSize = [[[self document] site] integerForKey:@"sourceOutlineSize"];
// TODO: set split view position
    
    
    // Tie the web content area to the source list's selection
    [[self webContentAreaController] bind:@"selectedPages"
                                 toObject:[self siteOutlineViewController]
                              withKeyPath:@"pagesController.selectedObjects"
                                  options:nil];
	
	// Link Popup in address bar
	//		[[oLinkPopup cell] setUsesItemFromMenu:NO];
	//		[oLinkPopup setIconImage:[NSImage imageNamed:@"links"]];
	//		[oLinkPopup setShowsMenuWhenIconClicked:YES];
	//		[oLinkPopup setArrowImage:nil];	// we have our own arrow, thank you
	
	
	
	// Hide address bar if it's hidden (it's showing to begin with, in the nib)
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(anyWindowWillClose:)
												 name:NSWindowWillCloseNotification
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateBuyNow:)
												 name:kKSLicenseStatusChangeNotification
											   object:nil];
	[self updateBuyNow:nil];	// update them now
	
	
	
	[self showInfo:[[NSUserDefaults standardUserDefaults] boolForKey:@"DisplayInfo"]];
	
	myLastClickedPoint = NSZeroPoint;
	
	// register for updates
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateSelectedItemForDocWindow:)
												 name:kKTItemSelectedNotification
											   object:nil];
	
	//	[[NSNotificationCenter defaultCenter] addObserver:self
	//											 selector:@selector(infoWindowMayNeedRefreshing:)
	//												 name:kKTInfoWindowMayNeedRefreshingNotification
	//											   object:nil];	
	
	// Check for missing media
	[self performSelector:@selector(checkForMissingMedia) withObject:nil afterDelay:0.0];
	
	// Put a gradient border at the bottom of the window
	[[self window] setContentBorderThickness:93.0 forEdge:NSMinYEdge];
	
	// LAST: clear the undo stack
	[[self document] performSelector:@selector(processPendingChangesAndClearChangeCount)
						  withObject:nil
						  afterDelay:0.0];
}

#pragma mark -
#pragma mark Controller Chain

- (id <KTDocumentControllerChain>)parentController { return nil; }

- (NSArray *)childControllers { return [[_childControllers copy] autorelease]; }

- (void)addChildController:(KTDocViewController *)controller
{
    OBPRECONDITION(controller);
    OBPRECONDITION(![controller parentController]); // The controller shouldn't already have a parent
    
    
    // Patch responder chain
    NSResponder *previousResponder = [_childControllers lastObject];
    if (!previousResponder) previousResponder = self;
    [previousResponder setNextResponder:controller insert:YES];
    
    
    // Add to controller chain
    [controller setParentController:self];
    [_childControllers addObject:controller];
}

- (void)removeChildController:(KTDocViewController *)controller
{
    unsigned index = [_childControllers indexOfObjectIdenticalTo:controller];
    if (index != NSNotFound)
    {
        // Patch responder chain
        NSResponder *previousResponder = (index > 0) ? [_childControllers objectAtIndex:(index - 1)] : self;
        [previousResponder setNextResponder:[controller nextResponder]];
        [controller setNextResponder:nil];
        
        
        // Remove from controller chain
        [controller setParentController:nil];
        [_childControllers removeObjectAtIndex:index];
    }
}

- (void)removeAllChildControllers
{
    // Patch responder chain
    KTDocViewController *lastController = [_childControllers lastObject];
    if (lastController)
    {
        [self setNextResponder:[lastController nextResponder]];
    }
    
    [_childControllers makeObjectsPerformSelector:@selector(setNextResponder:) withObject:nil];
    
    
    // Dump controllers
    [_childControllers makeObjectsPerformSelector:@selector(setParentController:) withObject:nil];
    [_childControllers removeAllObjects];
}

/*	We observe notifications from the document's undo manager
 */
- (void)setDocument:(NSDocument *)document
{
	// Throw away any existing plugin Inspector manager we might have otherwise it will attempt to access an invalid
	// managed object context later.
	[myPluginInspectorViewsManager release];	myPluginInspectorViewsManager = nil;
	
	
	// Default behaviour
	[super setDocument:document];
	
	
	// Alert sub-controllers to the change
    [[self childControllers] makeObjectsPerformSelector:@selector(setDocument:) withObject:[self document]];
}

- (KTDocWindowController *)windowController { return self; }

#pragma mark individual controllers

@synthesize siteOutlineViewController = _siteOutlineViewController;
- (void)setSiteOutlineViewController:(SVSiteOutlineViewController *)controller
{
	// Set up the new controller
	[controller retain];
	[_siteOutlineViewController release];   _siteOutlineViewController = controller;
	
	[controller setRootPage:[[[self document] site] root]];
}

@synthesize webContentAreaController = _webContentAreaController;
- (void)setWebContentAreaController:(SVWebContentAreaController *)controller
{
    [[self webContentAreaController] setDelegate:nil];
    
    [controller retain];
    [_webContentAreaController release],   _webContentAreaController = controller;
    
    [controller setDelegate:self];
}

#pragma mark -
#pragma mark Window Title

/*  We append the title of our current content to the default. This gives a similar effect to the titlebar in a web browser.
 */
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
    SVWebContentAreaController *contentController = [self webContentAreaController];
    if ([contentController selectedViewController] == [contentController webViewLoadController])
    {
        NSString *contentTitle = [[contentController selectedViewController] title];
        if ([contentTitle length] > 0)
        {
            displayName = [displayName stringByAppendingFormat:
                           @" — %@",    // yes, that's an em-dash
                           contentTitle];
        }
	}
    
    return displayName;
}

- (void)webContentAreaControllerDidChangeTitle:(SVWebContentAreaController *)controller;
{
    [self synchronizeWindowTitleWithDocumentName];
}

#pragma mark -
#pragma mark Missing Media

- (void)checkForMissingMedia
{
	@try	// Called once the window is on-screen via a delayedPerformSelector. Therefore we have to manage exceptions ourself.
    {
        // Check for missing media files. If any are missing alert the user
        NSSet *missingMedia = [[(KTDocument *)[self document] mediaManager] missingMediaFiles];
        if (missingMedia && [missingMedia count] > 0)
        {
            KTMissingMediaController *missingMediaController =
			[[KTMissingMediaController alloc] initWithWindowNibName:@"MissingMedia"];	// We'll release it after closing the sheet
            
            [missingMediaController setMediaManager:[(KTDocument *)[self document] mediaManager]];
            
            NSArray *sortedMissingMedia = [missingMedia allObjects];    // Not actually performing any sorting
            [missingMediaController setMissingMedia:sortedMissingMedia];
            
            [NSApp beginSheet:[missingMediaController window]
               modalForWindow:[self window]
                modalDelegate:self
               didEndSelector:@selector(missingMediaSheetDidEnd:returnCode:contextInfo:)
                  contextInfo:NULL];
        }
    }
    @catch (NSException *exception)
    {
        [NSApp reportException:exception];
    }
}

- (void)missingMediaSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
{
	[sheet orderOut:self];
	[[sheet windowController] autorelease];
	
	if (returnCode == 0)
	{
		[[self window] performClose:self]; 
	}
}

#pragma mark -
#pragma mark Public Functions


- (void)updatePopupButtonSizesSmall:(BOOL)aSmall;
{
	NSSize iconSize = aSmall ? NSMakeSize(16.0,16.0) : NSMakeSize(32.0, 32.0);
	
	NSArray *popupButtonsToAdjust = [NSArray arrayWithObjects:
		[self addPagePopUpButton],
		[self addPageletPopUpButton],
		[self addCollectionPopUpButton],
		nil];
	NSEnumerator *theEnum = [popupButtonsToAdjust objectEnumerator];
	RYZImagePopUpButton *aPopup;
	
	NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
	[style setMinimumLineHeight:iconSize.height];
	
	while (nil != (aPopup = [theEnum nextObject]) )
	{
		NSEnumerator *thePopupEnum = [[[aPopup menu] itemArray] objectEnumerator];
		NSMenuItem *item;
		
		while (nil != (item = [thePopupEnum nextObject]) )
		{
			NSImage *image = [item image];
			[image setSize:iconSize];
			
			// We also have to set the line height.
			NSMutableAttributedString *titleString
				= [[[NSMutableAttributedString alloc] initWithAttributedString:[item attributedTitle]] autorelease];
			[titleString addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0,[titleString length])];
			[titleString addAttribute:NSBaselineOffsetAttributeName
								value:[NSNumber numberWithFloat:((([image size].height-[NSFont smallSystemFontSize])/2.0)+2.0)]
								range:NSMakeRange(0,[titleString length])];
			
			
			[item setAttributedTitle:titleString];
		}
	}
}

#pragma mark -
#pragma mark IBActions

- (IBAction)windowHelp:(id)sender
{
	[[NSApp delegate] showHelpPage:@"Link"];		// HELPSTRING
}

#pragma mark -
#pragma mark Design Chooser

@synthesize designChooserWindowController = designChooserWindowController_;

- (IBAction)chooseDesign:(id)sender
{
    [self showChooseDesignSheet:sender];
}

- (IBAction)showChooseDesignSheet:(id)sender
{
    if ( !designChooserWindowController_ )
    {
        designChooserWindowController_ = [[SVDesignChooserWindowController alloc] initWithWindowNibName:@"SVDesignChooser"];
        [[self document] addWindowController:designChooserWindowController_];
    }
    
    [designChooserWindowController_ displayAsSheet];
}

#pragma mark -
#pragma mark Other

- (IBAction)toggleEditingControlsShown:(id)sender
{
    // set value
	BOOL value = [[self document] displayEditingControls];
	BOOL newValue = !value;
	[[self document] setDisplayEditingControls:newValue];

	// update UI
	[self updateToolbar];
	[[self webViewController] reloadWebView];
}

- (IBAction)toggleInfoShown:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	// reverse the flag in defaults
	BOOL value = [defaults boolForKey:@"DisplayInfo"];
	BOOL newValue = !value;
	[defaults setBool:newValue forKey:@"DisplayInfo"];
	
	// set menu to opposite of flag
	if ( newValue )
	{
		[[NSApp delegate] setDisplayInfoMenuItemTitle:KTHideInfoMenuItemTitle];
	}
	else
	{
		[[NSApp delegate] setDisplayInfoMenuItemTitle:KTShowInfoMenuItemTitle];
	}
	
	// display info, if appropriate
	[self showInfo:newValue];
}


- (IBAction)toggleSmallPageIcons:(id)sender
{
	BOOL value = [[self document] displaySmallPageIcons];
    [[self document] setDisplaySmallPageIcons:!value];
}

#pragma mark Page Actions

/*! adds a new page to site outline, obtaining its class from representedObject */
- (IBAction)addPage:(id)sender
{
    // LOG((@"%@: addPage using bundle: %@", self, [sender representedObject]));
	KTElementPlugin *plugin = nil;
	if ( [sender respondsToSelector:@selector(representedObject)] )
	{
		plugin = [sender representedObject];
	}
	
	if ( nil != plugin )
    {
		/// Case 17992, we now pass in a context to nearestParent
		KTPage *nearestParent = [self nearestParent:[[self document] managedObjectContext]];
		if ( ![nearestParent isKindOfClass:[KTPage class]] )
		{
			NSLog(@"unable to addPage: nearestParent is nil");
			return;
		}
		
		KTPage *page = [KTPage insertNewPageWithParent:nearestParent 
									   plugin:plugin];
		
		if (page)
		{
			// Insert the page
            [self insertPage:page parent:nearestParent];
            
            // Make the Site Outline display the new item nicely
			[[[self siteOutlineViewController] pagesController] setSelectedObjects:[NSArray arrayWithObject:page]];
		}
		else
		{
			NSLog(@"unable to addPage: unable to create Page");
			return;
		}
	}
	else
    {
		NSLog(@"unable to addPage: sender has no representedObject");
		return;
    }
}

/*! adds a new pagelet to current page, obtaining its class from representedObject */
- (IBAction)addPagelet:(id)sender
{
    //LOG((@"%@: addPagelet using bundle: %@", self, [sender representedObject]));
	KTElementPlugin *pageletPlugin = nil;
	
	if ([sender respondsToSelector:@selector(representedObject)])
	{
		pageletPlugin = [sender representedObject];
	}
	
	if (pageletPlugin && [pageletPlugin isKindOfClass:[KTElementPlugin class]])
    {
		KTPage *targetPage = [[[self siteOutlineViewController] pagesController] selectedPage];
		if (nil == targetPage)
		{
			// if nothing is selected, treat as if the root folder were selected
			targetPage = [[[self document] site] root];
		}
		
		KTPagelet *pagelet = [KTPagelet pageletWithPage:targetPage plugin:pageletPlugin];
		
		if ( nil != pagelet )
		{
			[self insertPagelet:pagelet toSelectedItem:targetPage];
		}
		else
		{
			[NSException raise:kKareliaDocumentException format:@"unable to create Pagelet"];
		}
	}
	else
    {
		[NSException raise:kKareliaDocumentException
							  reason:@"sender has no representedObject"
							userInfo:[NSDictionary dictionaryWithObject:sender forKey:@"sender"]];
    }
}


/*! adds a new collection to site outline, obtaining the information of a dictionary
from representedObject */

// TODO: Perhaps a lot more of this logic ought to be moved to KTPage+Operations.m


- (IBAction)addCollection:(id)sender
{
	OBASSERTSTRING( [sender respondsToSelector:@selector(representedObject)], @"Sender needs to have a representedObject" );
	
	NSDictionary *presetDict= [sender representedObject];
	NSString *identifier = [presetDict objectForKey:@"KTPresetIndexBundleIdentifier"];
	KTIndexPlugin *indexPlugin = identifier ? [KTIndexPlugin pluginWithIdentifier:identifier] : nil;
	
    if ( nil != indexPlugin )
    {		
		NSBundle *indexBundle = [indexPlugin bundle];
		// Figure out page type to construct based on info plist.  Be  a bit forgiving if not found.
		NSString *pageIdentifier = [presetDict objectForKey:@"KTPreferredPageBundleIdentifier"];
		if (nil == pageIdentifier)
		{
			pageIdentifier = [indexBundle objectForInfoDictionaryKey:@"KTPreferredPageBundleIdentifier"];
		}
		KTElementPlugin *pagePlugin = pageIdentifier ? [KTElementPlugin pluginWithIdentifier:pageIdentifier]  : nil;
		if (nil == pagePlugin)
		{
			pageIdentifier = [[NSUserDefaults standardUserDefaults] objectForKey:@"DefaultIndexBundleIdentifier"];
			pagePlugin = pageIdentifier ? [KTElementPlugin pluginWithIdentifier:pageIdentifier] : nil;
		}
		if (nil == pagePlugin)
		{
			[NSException raise: NSInternalInconsistencyException
						format: @"Unable to create page of type %@.",
				pageIdentifier];
		}
		
		/// Case 17992, nearestParent method now requires we pass in a context
		KTPage *nearestParent = [self nearestParent:[[self document] managedObjectContext]];
		/// Case 17992, added assert to better detect source of exception
		OBASSERTSTRING((nil != nearestParent), @"nearestParent should not be nil, root at worst");
		
		KTPage *indexPage = [KTPage insertNewPageWithParent:nearestParent plugin:pagePlugin];
		[indexPage setBool:YES forKey:@"isCollection"]; // Duh!
		
		// Now set the index on the page
		[indexPage setWrappedValue:identifier forKey:@"collectionIndexBundleIdentifier"];
		Class indexToAllocate = [indexBundle principalClassIncludingOtherLoadedBundles:YES];
		KTAbstractIndex *theIndex = [[((KTAbstractIndex *)[indexToAllocate alloc]) initWithPage:indexPage plugin:indexPlugin] autorelease];
		[indexPage setIndex:theIndex];
		
		
		// Now re-set title of page to be the appropriate untitled name
		NSString *englishPresetTitle = [presetDict objectForKey:@"KTPresetUntitled"];
		NSString *presetTitle = [indexBundle localizedStringForKey:englishPresetTitle value:englishPresetTitle table:nil];
		
		[indexPage setTitleText:presetTitle];
		
		NSDictionary *pageSettings = [presetDict objectForKey:@"KTPageSettings"];
		[indexPage setValuesForKeysWithDictionary:pageSettings];
		
		[self insertPage:indexPage parent:nearestParent];
		
		
		// Generate a first child page if desired
		NSString *firstChildIdentifier = [presetDict valueForKeyPath:@"KTFirstChildSettings.pluginIdentifier"];
		if (firstChildIdentifier && [firstChildIdentifier isKindOfClass:[NSString class]])
		{
			NSMutableDictionary *firstChildProperties =
				[NSMutableDictionary dictionaryWithDictionary:[presetDict objectForKey:@"KTFirstChildSettings"]];
			[firstChildProperties removeObjectForKey:@"pluginIdentifier"];
			
			KTPage *firstChild = [KTPage insertNewPageWithParent:indexPage
												 plugin:[KTElementPlugin pluginWithIdentifier:firstChildIdentifier]];
			
			NSEnumerator *propertiesEnumerator = [firstChildProperties keyEnumerator];
			NSString *aKey;
			while (aKey = [propertiesEnumerator nextObject])
			{
				id aProperty = [firstChildProperties objectForKey:aKey];
				if ([aProperty isKindOfClass:[NSString class]])
				{
					aProperty = [indexBundle localizedStringForKey:aProperty value:nil table:@"InfoPlist"];
				}
				
				[firstChild setValue:aProperty forKey:aKey];
			}
		}
		
		
		// Any collection with an RSS feed should have an RSS Badge.
		if ([pageSettings boolForKey:@"collectionSyndicate"])
		{
			NSNumber *includeRSSBadge = [presetDict objectForKey:@"KTIncludeRSSBadge"];
			if (!includeRSSBadge || [includeRSSBadge boolValue])
			{
				// Make the initial RSS badge
				NSString *initialBadgeBundleID = [[NSUserDefaults standardUserDefaults] objectForKey:@"DefaultRSSBadgeBundleIdentifier"];
				if (nil != initialBadgeBundleID && ![initialBadgeBundleID isEqualToString:@""])
				{
					KTElementPlugin *badgePlugin = [KTElementPlugin pluginWithIdentifier:initialBadgeBundleID];
					if (badgePlugin)
					{
						[KTPagelet pageletWithPage:indexPage plugin:badgePlugin];
					}
				}
			}
		
		
			// Give weblogs special introductory text
			if ([[presetDict objectForKey:@"KTPresetIndexBundleIdentifier"] isEqualToString:@"sandvox.GeneralIndex"])
			{
				NSString *intro = NSLocalizedString(@"<p>This is a new weblog. You can replace this text with an introduction to your blog, or just delete it if you wish. To add an entry to the weblog, add a new page using the \\U201CPages\\U201D button in the toolbar. For more information on blogging with Sandvox, please have a look through our <a href=\"help:Blogging_with_Sandvox\">help guide</a>.</p>",
													"Introductory text for Weblogs");
				
				[indexPage setValue:intro forKey:@"richTextHTML"];
			}
		}
        
        
        // Expand the item in the Site Outline
        [[[self siteOutlineViewController] outlineView] expandItem:indexPage];
    }
    else
    {
		[NSException raise:kKareliaDocumentException reason:@"Unable to instantiate collection"
							userInfo:[NSDictionary dictionaryWithObject:sender forKey:@"sender"]];
    }
}

/*! inserts aPage at the current selection */
- (void)insertPage:(KTPage *)aPage parent:(KTPage *)aCollection
{
	// add component to parent
	[aCollection addPage:aPage];
	
	[[[self siteOutlineViewController] pagesController] setSelectedObjects:[NSArray arrayWithObject:aPage]];
	
	// label undo and perserve the current selection
    if ( [aPage isCollection] )
	{
        [[[self document] undoManager] setActionName:NSLocalizedString(@"Add Collection", "action name for adding a collection")];
    }
    else
	{
		[[[self document] undoManager] setActionName:NSLocalizedString(@"Add Page", "action name for adding a page")];
    }
	
	if (([aPage boolForKey:@"includeInSiteMenu"])) 
	{
		////LOG((@"~~~~~~~~~ %@ calls markStale:kStaleFamily on root because included in site menu", NSStringFromSelector(_cmd)));
		//[[aCollection root] markStale:kStaleFamily];
	}
	else
	{
		////LOG((@"~~~~~~~~~ %@ calls markStale:kStaleFamily on '%@' because page inserted but not in site menu", NSStringFromSelector(_cmd), [aCollection titleText]));
		//[aCollection markStale:kStaleFamily];
	}
	
}

/*! inserts aPagelet at the current selection.  Just insert as a sidebar; let it be moved to callout */
- (void)insertPagelet:(KTPagelet *)aPagelet toSelectedItem:(KTPage *)selectedItem
{
	if ( [selectedItem isKindOfClass:[KTPage class]] )
	{
		if ([selectedItem includeSidebar] || [selectedItem includeCallout]) {
			//[selectedItem insertPagelet:aPagelet atIndex:0];
			/// There's no need to actually insert the pagelet, since creating it on this page did the job. Mike.
		}
		else {
            NSBeep();
		}
	}
	else
	{
		RAISE_EXCEPTION(kKareliaDocumentException, @"selectedItem is of unknown class", [NSDictionary dictionaryWithObject:selectedItem forKey:@"selectedItem"]);
		return;
	}
	
	// add component to parent
	
	// label undo and perserve the current selection
	[[[self document] undoManager] setActionName:NSLocalizedString(@"Add Pagelet", @"action name for adding a page")];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:kKTItemSelectedNotification object:aPagelet];
}

/*! group the selection in a new summary */
- (void)group:(id)sender
{
	NSArray *selectedPages = [[[[[self siteOutlineViewController] pagesController] selectedObjects] retain] autorelease];	// Hang onto it for length of method
	
	// This shouldn't happen
	if ([selectedPages count] == 0)
	{
		NSBeep();
		NSLog(@"Unable to create group: no selection to group.");
		return;
	}
	
	
	// It is not possible to make a group containing root
	OBASSERTSTRING(![selectedPages containsObject:[[[self document] site] root]], @"Can't create a group containing root");
	
	
	KTPage *firstSelectedPage = [selectedPages objectAtIndex:0];
	
	// our group's parent will be the original parent of firstSelectedPage
	KTPage *parentCollection = [(KTPage *)firstSelectedPage parent];
	if ( (nil == parentCollection) || (nil == [[parentCollection site] root]) )
	{
		NSLog(@"Unable to create group: could not determine parent collection.");
		return;
	}
	
	// create a new summary
	KTElementPlugin *collectionPlugin = nil;
	if ( [sender respondsToSelector:@selector(representedObject)] )
	{
		collectionPlugin = [sender representedObject];
	}
	
	if (!collectionPlugin)
	{
		NSString *defaultIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultIndexBundleIdentifier"];
		collectionPlugin = defaultIdentifier ? [KTIndexPlugin pluginWithIdentifier:defaultIdentifier] : nil;
	}
	OBASSERTSTRING(collectionPlugin, @"Must have a new collection plug-in to group the pages into");
	
	
	NSBundle *collectionBundle = [collectionPlugin bundle];
	NSString *pageIdentifier = [collectionBundle objectForInfoDictionaryKey:@"KTPreferredPageBundleIdentifier"];
	KTElementPlugin *pagePlugin = pageIdentifier ? [KTElementPlugin pluginWithIdentifier:pageIdentifier] : nil;
	if ( nil == pagePlugin )
	{
		pageIdentifier = [[NSUserDefaults standardUserDefaults] objectForKey:@"DefaultIndexBundleIdentifier"];
		pagePlugin = pageIdentifier ? [KTElementPlugin pluginWithIdentifier:pageIdentifier] : nil;
	}
	if ( nil == pagePlugin )
	{
		NSLog(@"Unable to create group: could not locate default index.");
		return;
	}
	
	///////////////////////////////////////////////////////////////////////////////////////////////////
	// at this point, we should be good to go
	
	// first, remove the selectedPages from their parents
	// the selectedPages array will hold pointers so we don't lose them
	unsigned int i;
	for ( i=0; i < [selectedPages count]; i++ )
	{
		KTPage *page = [selectedPages objectAtIndex:i];
		[[page parent] removePage:page];
	}
	
	
	// now, create a new collection to hold selectedPages
	KTPage *collection = [KTPage insertNewPageWithParent:parentCollection 
										 plugin:pagePlugin];
	
	
	[collection setValue:[collectionBundle bundleIdentifier] forKey:@"collectionIndexBundleIdentifier"];
	
// FIXME: we should load up the properties from a KTPreset
	
	Class indexToAllocate = [collectionBundle principalClassIncludingOtherLoadedBundles:YES];
	KTAbstractIndex *theIndex = [[((KTAbstractIndex *)[indexToAllocate alloc]) initWithPage:collection plugin:collectionPlugin] autorelease];
	[collection setIndex:theIndex];
	[collection setInteger:KTCollectionUnsorted forKey:@"collectionSortOrder"];				
	[collection setBool:YES forKey:@"isCollection"];
	[collection setBool:NO forKey:@"includeTimestamp"];
	
	// insert the new collection
	[parentCollection addPage:collection];
	
	// add our selectedPages back to the new collection
	for ( i=0; i < [selectedPages count]; i++ )
	{
		KTPage *page = [selectedPages objectAtIndex:i];
		[collection addPage:page];
	}            
	
	[[[self siteOutlineViewController] pagesController] setSelectedObjects:[NSSet setWithObject:collection]];
	
	// expand the new collection
	[[[self siteOutlineViewController] outlineView] expandItem:collection];
	
	// tidy up the undo stack with a relevant name
	[[[self document] undoManager] setActionName:NSLocalizedString(@"Group", @"action name for grouping selected items")];
}

- (IBAction)insertList:(id)sender
{
    [[[self webViewController] webView] replaceSelectionWithMarkupString:@"<p><ul><li></li></ul></p>"];
}

- (IBAction)insert2Table:(id)sender
{
    [[[self webViewController] webView] replaceSelectionWithMarkupString:@"<table><tr><td></td><td></td></tr></table>"];
}

#pragma mark -
#pragma mark Action Validation

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    return YES;
    
	OFF((@"KTDocWindowController validateMenuItem:%@ %@", [menuItem title], NSStringFromSelector([menuItem action])));
	SEL itemAction = [menuItem action];
		
	// File menu handled by KTDocument
		
	// Edit menu
	
	// "Paste" paste:
	if ( itemAction == @selector(paste:) )
	{
		{
			NSArray *selectedPages = [[[self siteOutlineViewController] pagesController] selectedObjects];
			if (1 != [selectedPages count])
			{
				return NO;	// can't paste if zero or >1 pages selected
			}
				
			KTPage *selectedPage = [selectedPages objectAtIndex:0];
			if ( [self canPastePages] )
			{
				return [selectedPage isCollection];
			}
			else if ( [self canPastePagelets] )
			{
				return ([selectedPage includeSidebar] || [selectedPage includeCallout]);
			}
			else
			{
				return NO;
			}
		}
	}	
	
	// "Paste" pasteAsRichText: NB: also intercepts general "paste" command
	else if ( itemAction == @selector(pasteAsRichText:) )
	{
		// check the general pasteboard to see if there are any pages on it
		NSPasteboard *generalPboard = [NSPasteboard generalPasteboard];
		if ( nil != [generalPboard availableTypeFromArray:[NSArray arrayWithObject:kKTPagesPboardType]] )
		{
			return YES;
		}
		else
		{
			return NO;
		}
	}
	
	// "Create Link..." showLinkPanel:
	else if (itemAction == @selector(showLinkPanel:))
	{
		NSString *title;
		BOOL result = [[self webViewController] validateCreateLinkItem:menuItem title:&title];
		[menuItem setTitle:title];
		return result;
	}
	
	// View menu
	// "Hide Designs" toggleDesignsShown:
    else if (itemAction == @selector(toggleDesignsShown:))
    {
        if ([[self document] showDesigns])
        {
            [menuItem setTitle:NSLocalizedString(@"Hide Designs", @"menu title to hide designs bar")];
        }
        else
        {
            [menuItem setTitle:NSLocalizedString(@"Show Designs", @"menu title to show design bar")];
        }
    }
    
    else if (itemAction == @selector(toggleEditingControlsShown:))
    {
        if ([[self document] displayEditingControls])
        {
            [menuItem setTitle:NSLocalizedString(@"Hide Editing Markers", @"menu title to hide Editing Markers")];
        }
        else
        {
            [menuItem setTitle:NSLocalizedString(@"Show Editing Markers", @"menu title to show Editing Markers")];
        }
    }
	
	// "Hide Site Outline" toggleSiteOutlineShown:
	else if (itemAction == @selector(toggleSiteOutlineShown:))
	{
		if ([self sidebarIsCollapsed])
        {
            [menuItem setTitle:NSLocalizedString(@"Show Site Outline", @"menu title to show site outline")];
            [menuItem setToolTip:NSLocalizedString(@"Shows the outline of the site on the left side of the window. Window must be wide enough to accomodate it.", @"Tooltip: menu tooltip to show site outline")];
        }
        else
        {
            [menuItem setTitle:NSLocalizedString(@"Hide Site Outline", @"menu title to hide site outline")];
            [menuItem setToolTip:NSLocalizedString(@"Collapses the outline of the site from the left side of the window.", @"menu tooltip to hide site outline")];
        }
	}
	
	// "Use Small Page Icons" toggleSmallPageIcons:
    else if ( itemAction == @selector(toggleSmallPageIcons:) )
	{
		[menuItem setState:
			([[self document] displaySmallPageIcons] ? NSOnState : NSOffState)];
		return YES;	// enabled if we can see the site outline
	}
	
	// Site menu items
    else if (itemAction == @selector(addPage:))
    {
        return YES;
    }
    else if (itemAction == @selector(addPagelet:))
    {
		KTPage *selectedPage = [[[self siteOutlineViewController] pagesController] selectedPage];
		return ([selectedPage sidebarChangeable]);
    }
	else if (itemAction == @selector(addCollection:))
    {
        return YES;
    }	
    else if (itemAction == @selector(exportSiteAgain:))
    {
        NSString *exportPath = [[[self document] site] lastExportDirectoryPath];
        return (exportPath != nil && [exportPath isAbsolutePath]);
    }
    
    // Other
    else if ( itemAction == @selector(group:) )
    {
        return ( ![[[[self siteOutlineViewController] pagesController] selectedObjects] containsObject:[[(KTDocument *)[self document] site] root]] );
    }
    else if ( itemAction == @selector(ungroup:) )
    {
		NSArray *selectedItems = [[[self siteOutlineViewController] pagesController] selectedObjects];
        return ( (1==[selectedItems count])
				 && ([selectedItems objectAtIndex:0] != [[(KTDocument *)[self document] site] root])
				 && ([[selectedItems objectAtIndex:0] isKindOfClass:[KTPage class]]) );
    }
	
	// "Visit Published Site" visitPublishedSite:
	else if ( itemAction == @selector(visitPublishedSite:) ) 
	{
		NSURL *siteURL = [[[[self document] site] hostProperties] siteURL];
		return (nil != siteURL);
	}
	
	// "Visit Published Page" visitPublishedPage:
	else if ( itemAction == @selector(visitPublishedPage:) ) 
	{
		NSURL *pageURL = [[[[self siteOutlineViewController] pagesController] selectedPage] URL];
		return (nil != pageURL);
	}

	else if ( itemAction == @selector(submitSiteToDirectory:) ) 
	{
		NSURL *siteURL = [[[[self document] site] hostProperties] siteURL];
		return (nil != siteURL);
	}
	
	// Window menu
	// "Show Inspector" toggleInfoShown:
	
	// Help menu
	// Debug menu
    // Contextual menu
	else if ( (itemAction == @selector(cutViaContextualMenu:))
			  || (itemAction == @selector(copyViaContextualMenu:))
			  || (itemAction == @selector(deleteViaContextualMenu:))
			  || (itemAction == @selector(duplicateViaContextualMenu:)) )
	{
        id context = [menuItem representedObject];
        id selection = [context valueForKey:kKTSelectedObjectsKey];
		
		if ( ![selection containsRoot] )
		{
			return YES;
		}
		else
		{
			return NO;
		}
	}
    else if ( itemAction == @selector(pasteViaContextualMenu:) )
    {
        if ( ![self canPastePages] )
        {
            return NO;
        }
        
        id context = [menuItem representedObject];
        id selection = [context valueForKey:kKTSelectedObjectsKey];
        if ( [selection isKindOfClass:[NSArray class]] )
        {
            KTPage *firstPage = [selection objectAtIndex:0];
            if ( [firstPage isCollection] )
            {
                return YES;
            }
            else
            {
                return NO;
            }
        }
        else
        {
            KTPage *page = selection;
            if ( [page isCollection] )
            {
                return YES;
            }
            else
            {
                return NO;
            }
        }
    }

	// DEFAULT: let webKit handle it
	else
	{
		return YES;
	}
    
    return YES;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem
{
	if ( [toolbarItem action] == @selector(addPage:) )
    {
        return YES;
    }
    else if ( [toolbarItem action] == @selector(addCollection:) )
    {
        return YES;
    }
    else if ( [toolbarItem action] == @selector(groupAsCollection:) )
    {
        return ( ![[[[self siteOutlineViewController] pagesController] selectedObjects] containsObject:[[(KTDocument *)[self document] site] root]] );
    }
    else if ( [toolbarItem action] == @selector(group:) )
    {
        return ( ![[[[self siteOutlineViewController] pagesController] selectedObjects] containsObject:[[(KTDocument *)[self document] site] root]] );
    }
    else if ( [toolbarItem action] == @selector(ungroup:) )
    {
		NSArray *selectedItems = [[[self siteOutlineViewController] pagesController] selectedObjects];
        return ( (1==[selectedItems count])
				 && ([selectedItems objectAtIndex:0] != [[(KTDocument *)[self document] site] root])
				 && ([[selectedItems objectAtIndex:0] isKindOfClass:[KTPage class]]) );
    }
    // Validate the -publishSiteFromToolbar: item here because -flagsChanged: doesn't catch all edge cases
    else if ([toolbarItem action] == @selector(publishSiteFromToolbar:))
    {
        [toolbarItem setLabel:
         ([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) ? TOOLBAR_PUBLISH_ALL : TOOLBAR_PUBLISH];
    }
    else if ( [toolbarItem action] == @selector(toggleDesignsShown:) )
    {
        return YES;
    }
    
    return YES;
}

#pragma mark -
#pragma mark Selection

- (void)postSelectionAndUpdateNotificationsForItem:(id)aSelectableItem
{
	[[NSNotificationCenter defaultCenter] postNotificationName:kKTItemSelectedNotification 
														object:aSelectableItem];
}

- (void)updateSelectedItemForDocWindow:(NSNotification *)aNotification
{
	OFF((@"windowController shows you selected %@", [[aNotification object] managedObjectDescription]));
	id selectedObject = [aNotification object];
	
	if ([selectedObject respondsToSelector:@selector(DOMNode)])
	{
		DOMNode *dn = [selectedObject DOMNode];
		DOMDocument *dd = [dn ownerDocument];
		DOMDocument *myDD = [[[[self webViewController] webView] mainFrame] DOMDocument];
		if (dd != myDD)
		{
			return;		// notification is coming from a different dom document, thus differnt svx document
		}
	}
	
	if ( [selectedObject isKindOfClass:[KTInlineImageElement class]] )
	{
		[self setSelectedInlineImageElement:selectedObject];
	}
	else if ( [selectedObject isKindOfClass:[KTPagelet class]] )
	{
		[self setSelectedPagelet:selectedObject];
	}
	else	// KTPage
	{
		myDocumentVisibleRect = NSZeroRect;
		myHasSavedVisibleRect = YES;		// new page, so don't save the scroll position.
		[self setSelectedPagelet:nil];
		[self setSelectedInlineImageElement:nil];
	}
	
	//[self updateEditMenuItems];
}

#pragma mark -
#pragma mark Plugins

- (KTPluginInspectorViewsManager *)pluginInspectorViewsManager
{
	if (!myPluginInspectorViewsManager)
	{
		myPluginInspectorViewsManager = [[KTPluginInspectorViewsManager alloc] init];
	}
	
	return myPluginInspectorViewsManager;
}

#pragma mark -
#pragma mark Window Delegate

- (void)windowDidResize:(NSNotification *)aNotification
{
    NSWindow *window = [aNotification object];
	
	NSRect windowRect = [[window contentView] frame];
	NSSize windowSize = windowRect.size;
	
    if ( window == [self window] ) {
		[[NSUserDefaults standardUserDefaults] setObject:NSStringFromSize(windowSize)
												  forKey:@"DefaultDocumentWindowContentSize"];
    }
}

- (void)windowWillClose:(NSNotification *)notification;
{
    // Ignore windows not our own
    if ([notification object] != [self window])
    {
        return;
    }
    
    
	[self setSiteOutlineViewController:nil];
}

/*!	Notification that some window is closing
*/
- (void)anyWindowWillClose:(NSNotification *)aNotification
{
	id obj = [aNotification object];
	if (obj == [[KTInfoWindowController sharedControllerWithoutLoading] window])
	{
		NSRect frame = [obj frame];
		NSPoint topLeft = NSMakePoint(frame.origin.x, frame.origin.y+frame.size.height);
		NSString *topLeftAsString = NSStringFromPoint(topLeft);
		[[NSUserDefaults standardUserDefaults] setObject:topLeftAsString forKey:gInfoWindowAutoSaveName];

		[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"DisplayInfo"];
		[[NSApp delegate] setDisplayInfoMenuItemTitle:KTShowInfoMenuItemTitle];
	}
	else if (obj == [[iMediaBrowser sharedBrowserWithoutLoading] window])
	{
		[[NSApp delegate] setDisplayMediaMenuItemTitle:KTShowMediaMenuItemTitle];
	}
	else
	{
		// LOG((@"windowWillClose --> %@", [aNotification object]));
	}
}

#pragma mark -
#pragma mark Components

- (BOOL)addPagesViaDragToCollection:(KTPage *)aCollection atIndex:(int)anIndex draggingInfo:(id <NSDraggingInfo>)info
{
	// LOG((@"%@", NSStringFromSelector(_cmd) ));
    
	BOOL result = NO;	// set to YES if at least one item got processed
	int numberOfItems = [KTElementPlugin numberOfItemsToProcessDrag:info];
	
	/*
     /// Mike: I see no point in this artificial limit in 1.5
     int maxNumberDragItems = [defaults integerForKey:@"MaximumDraggedPages"];
     numberOfItems = MIN(numberOfItems, maxNumberDragItems);
     */
	KTPage *latestPage = nil; //only select the last page created
	
	
    //[[[self document] managedObjectContext] lockPSCAndSelf];
    // TODO: it would be nice if we could do the ordering insert just once ahead of time, rather than once per "insertPage:atIndex:"
    
    NSString *localizedStatus = NSLocalizedString(@"Creating pages...", "");
    KSProgressPanel *progressPanel = nil;
    if (numberOfItems > 3)
    {
        progressPanel = [[KSProgressPanel alloc] init];
        [progressPanel setMessageText:localizedStatus];
        [progressPanel setInformativeText:nil];
        [progressPanel setMinValue:0 maxValue:numberOfItems doubleValue:0];
        [progressPanel beginSheetModalForWindow:[self window]];
    }
    
    int i;
    for ( i = 0 ; i < numberOfItems ; i++ )
    {
        NSAutoreleasePool *poolForEachDrag = [[NSAutoreleasePool alloc] init];
        
        [progressPanel setMessageText:localizedStatus];
        [progressPanel setDoubleValue:i];
        
        Class <KTDataSource> bestSource = [KTElementPlugin highestPriorityDataSourceForDrag:info index:i isCreatingPagelet:NO];
        if ( nil != bestSource )
        {
            NSMutableDictionary *dragDataDictionary = [NSMutableDictionary dictionary];
            [dragDataDictionary setValue:[info draggingPasteboard] forKey:kKTDataSourcePasteboard];	// always include this!
            
            BOOL didPerformDrag;
            didPerformDrag = [bestSource populateDataSourceDictionary:dragDataDictionary fromPasteboard:[info draggingPasteboard] atIndex:i forCreatingPagelet:NO];
            NSString *theBundleIdentifier = [[NSBundle bundleForClass:bestSource] bundleIdentifier];
            
            if ( didPerformDrag && theBundleIdentifier)
            {
                KTElementPlugin *thePlugin = [KTElementPlugin pluginWithIdentifier:theBundleIdentifier];
                if (thePlugin)
                {
                    [dragDataDictionary setObject:thePlugin forKey:kKTDataSourcePlugin];
                    
                    KTPage *newPage = [KTPage pageWithParent:aCollection
                                        dataSourceDictionary:dragDataDictionary
                              insertIntoManagedObjectContext:[[self document] managedObjectContext]];
                    
                    if (newPage)
                    {
                        // Insert the page where indicated
                        [aCollection addPage:newPage];
                        if (anIndex != NSOutlineViewDropOnItemIndex && [aCollection collectionSortOrder] == KTCollectionUnsorted)
                        {
                            [newPage moveToIndex:anIndex];
                        }
                        
                        
                        
                        if ( NSOutlineViewDropOnItemIndex != anIndex )
                        {
                            latestPage = newPage;
                        }
                        
                        // we're golden
                        result = YES;
                        
                        // Now see if we need to recurse; it's a collection
                        if ([[dragDataDictionary objectForKey:kKTDataSourceRecurse] boolValue])
                        {
                            NSString *defaultIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultIndexBundleIdentifier"];
                            KTIndexPlugin *indexPlugin = defaultIdentifier ? [KTIndexPlugin pluginWithIdentifier:defaultIdentifier] : nil;
                            NSBundle *indexBundle = [indexPlugin bundle];
                            
                            // FIXME: we should load up the properties from a KTPreset
                            
                            [newPage setValue:[indexBundle bundleIdentifier] forKey:@"collectionIndexBundleIdentifier"];
                            Class indexToAllocate = [indexBundle principalClassIncludingOtherLoadedBundles:YES];
                            KTAbstractIndex *theIndex = [[((KTAbstractIndex *)[indexToAllocate alloc]) initWithPage:newPage plugin:indexPlugin] autorelease];
                            [newPage setIndex:theIndex];
                            [newPage setBool:YES forKey:@"isCollection"]; // should this info be specified in the plist?
                            [newPage setBool:NO forKey:@"includeTimestamp"];		// collection should generally not have timestamp
                            
                            // At this point we should recurse ... deal with indexes, and whether it was photos
                        }
                        
                        // label undo last
                        [[[self document] undoManager] setActionName:NSLocalizedString(@"Drag from External Source",
                                                                                       "action name for dragging external objects to source outline")];
                    }
                    else
                    {
                        LOG((@"error: unable to create item of type: %@", theBundleIdentifier));
                    }
                }
                else
                {
                    LOG((@"error: datasource returned unknown bundle identifier: %@", theBundleIdentifier));
                }
            }
            else
            {
                LOG((@"%@ did not accept drop, no child returned", bestSource));
            }
        }
        else
        {
            LOG((@"No datasource agreed to handle types: %@", [[[info draggingPasteboard] types] description]));
        }
        
        [poolForEachDrag release];
    }
    
    [progressPanel endSheet];
    [progressPanel release];
    
	
	// if not dropping on an item, set the selection to the last page created
	if ( latestPage != nil )
	{
		[[[self siteOutlineViewController] pagesController] setSelectedObjects:[NSSet setWithObject:latestPage]];
	}
	
	// Done
	[KTElementPlugin doneProcessingDrag];
	
	return result;
}

#pragma mark -
#pragma mark Code Injection

- (KTCodeInjectionController *)masterCodeInjectionController
{
	if (!myMasterCodeInjectionController)
	{
		myMasterCodeInjectionController =
			[[KTCodeInjectionController alloc] initWithSiteOutlineController:[[self siteOutlineViewController] pagesController] master:YES];
		
		[[self document] addWindowController:myMasterCodeInjectionController];
	}
	
	return myMasterCodeInjectionController;
}

- (IBAction)showSiteCodeInjection:(id)sender
{
	[[self masterCodeInjectionController] showWindow:sender];
}

- (KTCodeInjectionController *)pageCodeInjectionController
{
	if (!myPageCodeInjectionController)
	{
		myPageCodeInjectionController =
			[[KTCodeInjectionController alloc] initWithSiteOutlineController:[[self siteOutlineViewController] pagesController] master:NO];
		
		[[self document] addWindowController:myPageCodeInjectionController];
	}
	
	return myPageCodeInjectionController;
}

- (IBAction)showPageCodeInjection:(id)sender
{
	[[self pageCodeInjectionController] showWindow:sender];
}

#pragma mark -
#pragma mark Support

- (void) updateBuyNow:(NSNotification *)aNotification
{
	if (nil == gRegistrationString)
	{
		if (!myBuyNowButton)
		{
			NSButton *newButton = [[self window] createBuyNowButton];
			myBuyNowButton = [newButton retain];
			[myBuyNowButton setAction:@selector(showRegistrationWindow:)];
			[myBuyNowButton setTarget:[NSApp delegate]];
		}
		[myBuyNowButton setHidden:NO];
	}
	else
	{
		[myBuyNowButton setHidden:YES];
	}
	
}

- (void)updateWebView:(id)sender;
{
    [[[self webContentAreaController] webViewLoadController] setNeedsLoad:YES];
}

// the goal here will be to clear the HTML markup from the pasteboard before pasting,
// if we can just get this to work!
- (void)handleEvent:(DOMEvent *)event;
{
	LOG((@"event= %@", event));
}

#pragma mark -
#pragma mark Inspector

/*!	Show the info, in whatever is the current configuration.  Close other things not showing.
*/
- (void)showInfo:(BOOL)inShow
{
	if (inShow)	// show separate info
	{
		KTInfoWindowController *sharedController = [KTInfoWindowController sharedController];
		[sharedController setAssociatedDocument:[self document]];
		if (nil != mySelectedInlineImageElement)
		{
			[sharedController setupViewStackFor:mySelectedInlineImageElement selectLevel:NO];
		}
		else if (nil != mySelectedPagelet)
		{
			[sharedController setupViewStackFor:mySelectedPagelet selectLevel:NO];
		}
		else if ([[[[self siteOutlineViewController] pagesController] selectedObjects] count] > 0)
		{
			[sharedController setupViewStackFor:[[[[self siteOutlineViewController] pagesController] selectedObjects] firstObjectKS]
                                    selectLevel:NO];
		}
		
		[sharedController putContentInWindow];
		
		if (![[sharedController window] isVisible])
		{
			NSString *topLeftAsString = [[NSUserDefaults standardUserDefaults] objectForKey:gInfoWindowAutoSaveName];
			if ( nil != topLeftAsString )
			{
				NSWindow *window = [sharedController window];
				NSPoint topLeft = NSPointFromString(topLeftAsString);
				NSRect screenRect = [[window screen] visibleFrame];
				NSRect frame = [window frame];
				frame.origin = topLeft;
				if (!NSContainsRect(screenRect, frame))
				{
					if (NSMaxX(frame) > NSMaxX(screenRect))
					{
						frame.origin.x -= (NSMaxX(frame) - NSMaxX(screenRect));	// right edge
					}
					if (NSMaxY(frame) > NSMaxY(screenRect))
					{
						frame.origin.y = NSMaxY(screenRect);	// top edge
					}
					if (NSMinX(frame) < NSMinX(screenRect))
					{
						frame.origin.x = NSMinX(screenRect);	// left edge
					}
					if (NSMinY(frame) < NSMinY(screenRect))
					{
						frame.origin.y = NSMinY(screenRect) + frame.size.height;	// bottom edge
					}
				}
				[window setFrameTopLeftPoint:frame.origin];
			}
			[sharedController showWindow:nil];
		}
	}
	else	// hide
	{
		KTInfoWindowController *sharedControllerMaybe = [KTInfoWindowController sharedControllerWithoutLoading];
 		if (sharedControllerMaybe)
		{

			NSRect frame = [[sharedControllerMaybe window] frame];
			NSPoint topLeft = NSMakePoint(frame.origin.x, frame.origin.y+frame.size.height);
			NSString *topLeftAsString = NSStringFromPoint(topLeft);
			[[NSUserDefaults standardUserDefaults] setObject:topLeftAsString forKey:gInfoWindowAutoSaveName];

			[[sharedControllerMaybe window] orderOut:nil];
		}
	}
}

@end

