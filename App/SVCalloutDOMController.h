//
//  SVCalloutDOMController.h
//  Sandvox
//
//  Created by Mike on 28/12/2009.
//  Copyright 2009 Karelia Software. All rights reserved.
//

#import "SVDOMController.h"


@interface SVCalloutDOMController : SVDOMController
{
  @private
    DOMElement  *_calloutContent;
}

@property(nonatomic, retain) DOMElement *calloutContentElement;

@end


#pragma mark -


@interface WEKWebEditorItem (SVCalloutDOMController)
- (SVCalloutDOMController *)calloutDOMController;
@end
