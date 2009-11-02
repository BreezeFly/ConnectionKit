//
//  SVWebEditorView.h
//  Sandvox
//
//  Created by Mike on 04/09/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

//  An SVWebEditorView object abstracts out some of the functionality we need in Sandvox for performing editing in a webview. With it, you should have no need to access the contained WebView directly; the editor should provide its own API as a wrapper.
//  The main thing we add to a standard WebView is the concept of selection. In this way SVWebEditorView is a lot like NSTableView and other collection classes; it knows how to display and handle arbitrary content, but relies on a datasource to provide them.


#import <WebKit/WebKit.h>
#import "SVWebEditorItemProtocol.h"
#import "SVWebEditorTextProtocol.h"


@protocol SVWebEditorViewDataSource, SVWebEditorViewDelegate;
@class SVWebEditorWebView;


@interface SVWebEditorView : NSView <NSUserInterfaceValidations>
{
  @private
    // Content
    SVWebEditorWebView              *_webView;
    id <SVWebEditorViewDataSource>  _dataSource;    // weak ref as you'd expect
    id <SVWebEditorViewDelegate>    _delegate;      // "
    BOOL    _isLoading;
    
    // Selection
    id <SVWebEditorText>    _focusedText;
    NSArray                 *_selectedItems;
    NSArray                 *_selectionParentItems;
    BOOL                    _isChangingSelectedItems;
    
    // Editing
    DOMRange        *_DOMRangeOfNextEdit;
    BOOL            _mouseUpMayBeginEditing;
    NSUndoManager   *_undoManager;
    
    // Drag & Drop
    BOOL        _isDragging;
    DOMNode     *_dragHighlightNode;
    DOMRange    *_dragCaretDOMRange;
    
    // Event Handling
    NSEvent *_mouseDownEvent;   // have to record all mouse down events in case they turn into a drag op
    BOOL    _isProcessingEvent;
}


#pragma mark Document

@property(nonatomic, readonly) DOMDocument *DOMDocument;


#pragma mark Loading Data

- (void)loadHTMLString:(NSString *)string baseURL:(NSURL *)URL;

// Blocks until either loading is finished or date is reached. Returns YES if the former.
- (BOOL)loadUntilDate:(NSDate *)date;

@property(nonatomic, readonly, getter=isLoading) BOOL loading;


#pragma mark Selection

@property(nonatomic, readonly) DOMRange *selectedDOMRange;

@property(nonatomic, retain, readonly) id <SVWebEditorText> focusedText;

@property(nonatomic, copy) NSArray *selectedItems;
@property(nonatomic, retain, readonly) id <SVWebEditorItem> selectedItem;
- (void)selectItems:(NSArray *)items byExtendingSelection:(BOOL)extendSelection;
- (void)deselectItem:(id <SVWebEditorItem>)item;

- (IBAction)deselectAll:(id)sender;


#pragma mark Editing

// We don't want to allow any sort of change unless the WebView is First Responder
- (BOOL)canEditText;
// WebKit doesn't supply any sort of -willFoo editing notifications, but we're in control now and can provide a pretty decent approximation.
- (void)willEditTextInDOMRange:(DOMRange *)range;
- (void)didChangeTextInDOMRange:(DOMRange *)range notification:(NSNotification *)notification;


#pragma mark Undo Support
// It is the responsibility of SVWebEditorTextBlocks to use these methods to control undo support as they modify the DOM
@property(nonatomic) BOOL allowsUndo;
- (void)removeAllUndoActions;


#pragma mark Cut, Copy & Paste
- (IBAction)cut:(id)sender;
- (IBAction)copy:(id)sender;
- (BOOL)copySelectedItemsToGeneralPasteboard;
// - (IBAction)paste:(id)sender;
- (IBAction)delete:(id)sender;


#pragma mark Drawing
// The editor contains a variety of subviews. When it needs the effect of drawing an overlay above them this method is called, telling you the view that is being drawn into, and where.
- (void)drawOverlayRect:(NSRect)dirtyRect inView:(NSView *)view;
- (void)drawSelectionRect:(NSRect)dirtyRect inView:(NSView *)view;


#pragma mark Getting Item Information

//  Queries the datasource
- (id <SVWebEditorItem>)itemAtPoint:(NSPoint)point;
- (id <SVWebEditorItem>)itemForDOMNode:(DOMNode *)node;
- (NSArray *)itemsInDOMRange:(DOMRange *)range;
- (id <SVWebEditorItem>)parentForItem:(id <SVWebEditorItem>)item;

- (id <SVWebEditorItem>)itemForDOMNode:(DOMNode *)node inItems:(NSArray *)items;


#pragma mark Setting the DataSource/Delegate

@property(nonatomic, assign) id <SVWebEditorViewDataSource> dataSource;
@property(nonatomic, assign) id <SVWebEditorViewDelegate> delegate;

@end


#pragma mark -


@interface SVWebEditorView (Dragging)

#pragma mark Dragging Destination

// Operates in a similar fashion to WebView's drag caret methods, but instead draw a big blue highlight around the node. To remove pass in nil
- (void)moveDragHighlightToDOMNode:(DOMNode *)node;
- (void)moveDragCaretToDOMRange:(DOMRange *)range;  // must be a collapsed range
- (void)removeDragCaret;


#pragma mark Drawing
- (void)drawDragCaretInView:(NSView *)view;


#pragma mark Layout
- (NSRect)rectOfDragCaret;


@end


#pragma mark -


@protocol SVWebEditorViewDataSource <NSObject>

/*!
 @method webEditorView:childrenOfItem:
 @param sender The SVWebEditorView object sending the message.
 @param item The item whose children to search for. Nil if after top-level items
 @result An array of SVWebEditorItem objects.
 */
- (NSArray *)webEditorView:(SVWebEditorView *)sender childrenOfItem:(id <SVWebEditorItem>)item;


/*  We locate text blocks on-demand based on a DOM range. It's expected the datasource will be maintaining its own list of such text blocks already.
 */
- (id <SVWebEditorText>)webEditorView:(SVWebEditorView *)sender
                      textBlockForDOMRange:(DOMRange *)range;

- (BOOL)webEditorView:(SVWebEditorView *)sender deleteItems:(NSArray *)items;

// Return something other than NSDragOperationNone to take command of the drop
- (NSDragOperation)webEditorView:(SVWebEditorView *)sender
      dataSourceShouldHandleDrop:(id <NSDraggingInfo>)dragInfo;

/*!
 @method webEditorView:writeItems:toPasteboard:
 @param sender
 @param items An array of SVWebEditorItem objects to be written
 @param pasteboard
 @result YES if the items could be written to the pasteboard
 */
- (BOOL)webEditorView:(SVWebEditorView *)sender
           writeItems:(NSArray *)items
         toPasteboard:(NSPasteboard *)pasteboard;

@end


#pragma mark -


@protocol SVWebEditorViewDelegate <NSObject>

- (void)webEditorViewDidFinishLoading:(SVWebEditorView *)sender;

// Much like -webView:didReceiveTitle:forFrame:
- (void)webEditorView:(SVWebEditorView *)sender didReceiveTitle:(NSString *)title;

 - (void)webEditorView:(SVWebEditorView *)webEditorView
handleNavigationAction:(NSDictionary *)actionInformation
               request:(NSURLRequest *)request;

@end

extern NSString *SVWebEditorViewSelectionDidChangeNotification;


#pragma mark -


@interface SVWebEditorView (SPI)

// Do NOT attempt to edit this WebView in any way. The whole point of SVWebEditorView is to provide a more structured API around a WebView's editing capabilities. You should only ever be modifying the WebView through the API SVWebEditorView and its Date Source/Delegate provides.
@property(nonatomic, retain, readonly) WebView *webView;

- (NSDragOperation)validateDrop:(id <NSDraggingInfo>)sender proposedOperation:(NSDragOperation)op;
@end


