



//
//  LSTopWindow.m
//  LSPlayer
//
//  Created by ls on 16/4/5.
//  Copyright © 2016年 song. All rights reserved.
//

#import "LSTopWindow.h"


@implementation LSTopWindow


-(void)setContentView:(UIView *)contentView
{
    _contentView=contentView;
    [self addSubview:contentView];
    
}
-(void)layoutSubviews
{
    [super layoutSubviews];
    
    self.contentView.frame=self.bounds;
}

@end
