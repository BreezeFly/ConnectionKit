//
//  SVHTMLElementController.h
//  Sandvox
//
//  Created by Mike on 24/11/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@class SVHTMLContext;

@interface SVHTMLElementController : NSController
{
  @private
    DOMHTMLElement  *_DOMElement;
    id              _representedObject;
    SVHTMLContext   *_context;
    
    DOMHTMLDocument *_DOMDocument;
}

#pragma mark Init

// For subclasses that know how to load HTML element from the document
- (id)initWithHTMLDocument:(DOMHTMLDocument *)document;
@property(nonatomic, retain, readonly) DOMHTMLDocument *HTMLDocument;

// Convenience method:
- (id)initWithHTMLElement:(DOMHTMLElement *)element;


#pragma mark DOM

@property(nonatomic, retain) DOMHTMLElement *HTMLElement;
- (void)loadHTMLElement;
- (BOOL)isHTMLElementLoaded;

- (void)update; //override to push changes through to the DOM
- (void)setNeedsUpdate; // call to mark for needing update. Instantaneous at the moment, but might not be in the future


#pragma mark Content
@property(nonatomic, retain) id representedObject;

@property(nonatomic, retain) SVHTMLContext *HTMLContext;


@end
