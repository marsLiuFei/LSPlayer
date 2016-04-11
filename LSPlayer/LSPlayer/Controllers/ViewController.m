//
//  ViewController.m
//  LSPlayer
//
//  Created by ls on 16/3/8.
//  Copyright © 2016年 song. All rights reserved.
//

#import "LSPlayerView.h"
#import "LSTableViewCell.h"
#import "ViewController.h"
#import <AFNetworking.h>
#import <UIImageView+AFNetworking.h>

#import "LSMediaModel.h"
#import "UIImage+Image.h"
@interface ViewController ()<UITableViewDelegate>

@property (nonatomic, strong) NSMutableArray* models;
@property (nonatomic, strong) LSTableViewCell* cell;
@end

@implementation ViewController

- (NSMutableArray*)models
{
    if (_models == nil) {
        _models = [NSMutableArray array];
    }
    return _models;
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController.navigationBar setBackgroundImage:[UIImage imageWithColor:[UIColor colorWithRed:0.727 green:1.000 blue:0.881 alpha:1.000]] forBarMetrics:UIBarMetricsDefault];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 200;
    
    AFHTTPSessionManager* manager = [AFHTTPSessionManager manager];
    [manager GET:@"http://c.m.163.com/nc/video/home/0-10.html" parameters:nil progress:^(NSProgress* _Nonnull downloadProgress) {
    }
        success:^(NSURLSessionDataTask* _Nonnull task, id _Nullable responseObject) {

            for (NSDictionary* dict in responseObject[@"videoList"]) {
                LSMediaModel* model = [[LSMediaModel alloc] initWithDictionary:dict];
                [self.models addObject:model];
            }
            [self.tableView reloadData];
            if (self.models.count) return ;
            //测试时地址有可能失效
            NSURL* url = [[NSBundle mainBundle] URLForResource:@"list.json" withExtension:nil];
            responseObject = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
            
            for (NSDictionary* dict in responseObject[@"videoList"]) {
                LSMediaModel* model = [[LSMediaModel alloc] initWithDictionary:dict];
                [self.models addObject:model];
            }
            [self.tableView reloadData];
        }
        failure:^(NSURLSessionDataTask* _Nullable task, NSError* _Nonnull error){

        }];
    //测试时地址有可能失效
    NSURL* url = [[NSBundle mainBundle] URLForResource:@"list.json" withExtension:nil];
    id responseObject = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    
    for (NSDictionary* dict in responseObject[@"videoList"]) {
        LSMediaModel* model = [[LSMediaModel alloc] initWithDictionary:dict];
        [self.models addObject:model];
    }
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView
{
    return self.models.count;
}
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    return 1;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    LSTableViewCell* cell = [LSTableViewCell cellWithTabelView:tableView];
    LSMediaModel* model = self.models[indexPath.section];
    cell.model = model;
    cell.index = indexPath.section;
    return cell;
}

- (CGFloat)tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section
{

    if (section==self.models.count-1) {
        return 10;
    }
    return 0.1;
}

-(CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 10;
}
@end
