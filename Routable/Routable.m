//
//  Routable.m
//  Routable
//
//  Created by Clay Allsopp on 4/3/13.
//  Copyright (c) 2013 TurboProp Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "Routable.h"

@implementation Routable

+ (instancetype)sharedRouter {
  static Routable *_sharedRouter = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    _sharedRouter = [[Routable alloc] init];
  });
  return _sharedRouter;
}

//really unnecessary; kept for backward compatibility.
+ (instancetype)newRouter {
  return [[self alloc] init];
}

@end

@interface RouterParams : NSObject

@property (readwrite, nonatomic, strong) UPRouterOptions *routerOptions;
@property (readwrite, nonatomic, strong) NSDictionary *openParams;
@property (readwrite, nonatomic, strong) NSDictionary *extraParams;
@property (readwrite, nonatomic, strong) NSDictionary *controllerParams;

@end

@implementation RouterParams

- (instancetype)initWithRouterOptions: (UPRouterOptions *)routerOptions openParams: (NSDictionary *)openParams extraParams: (NSDictionary *)extraParams{
  [self setRouterOptions:routerOptions];
  [self setExtraParams: extraParams];
  [self setOpenParams:openParams];
  return self;
}

- (NSDictionary *)controllerParams {
  NSMutableDictionary *controllerParams = [NSMutableDictionary dictionaryWithDictionary:self.routerOptions.defaultParams];
  [controllerParams addEntriesFromDictionary:self.extraParams];
  [controllerParams addEntriesFromDictionary:self.openParams];
  return controllerParams;
}
//fake getter. Not idiomatic Objective-C. Use accessor controllerParams instead
- (NSDictionary *)getControllerParams {
  return [self controllerParams];
}
@end

@interface UPRouterOptions ()

@property (readwrite, nonatomic, strong) Class openClass;           //注册的类
@property (readwrite, nonatomic, copy) RouterOpenCallback callback; //block 回调
@end

@implementation UPRouterOptions

//Explicit construction
+ (instancetype)routerOptionsWithPresentationStyle: (UIModalPresentationStyle)presentationStyle
                                   transitionStyle: (UIModalTransitionStyle)transitionStyle
                                     defaultParams: (NSDictionary *)defaultParams
                                            isRoot: (BOOL)isRoot
                                           isModal: (BOOL)isModal {
  UPRouterOptions *options = [[UPRouterOptions alloc] init];
  options.presentationStyle = presentationStyle;
  options.transitionStyle = transitionStyle;
  options.defaultParams = defaultParams;
  options.shouldOpenAsRootViewController = isRoot;
  options.modal = isModal;
  return options;
}
//Default construction; like [NSArray array]
+ (instancetype)routerOptions {
  return [self routerOptionsWithPresentationStyle:UIModalPresentationNone
                                  transitionStyle:UIModalTransitionStyleCoverVertical
                                    defaultParams:nil
                                           isRoot:NO
                                          isModal:NO];
}

//Custom class constructors, with heavier Objective-C accent
+ (instancetype)routerOptionsAsModal {
  return [self routerOptionsWithPresentationStyle:UIModalPresentationNone
                                  transitionStyle:UIModalTransitionStyleCoverVertical
                                    defaultParams:nil
                                           isRoot:NO
                                          isModal:YES];
}
+ (instancetype)routerOptionsWithPresentationStyle:(UIModalPresentationStyle)style {
  return [self routerOptionsWithPresentationStyle:style
                                  transitionStyle:UIModalTransitionStyleCoverVertical
                                    defaultParams:nil
                                           isRoot:NO
                                          isModal:NO];
}
+ (instancetype)routerOptionsWithTransitionStyle:(UIModalTransitionStyle)style {
  return [self routerOptionsWithPresentationStyle:UIModalPresentationNone
                                  transitionStyle:style
                                    defaultParams:nil
                                           isRoot:NO
                                          isModal:NO];
}
+ (instancetype)routerOptionsForDefaultParams:(NSDictionary *)defaultParams {
  return [self routerOptionsWithPresentationStyle:UIModalPresentationNone
                                  transitionStyle:UIModalTransitionStyleCoverVertical
                                    defaultParams:defaultParams
                                           isRoot:NO
                                          isModal:NO];
}
+ (instancetype)routerOptionsAsRoot {
  return [self routerOptionsWithPresentationStyle:UIModalPresentationNone
                                  transitionStyle:UIModalTransitionStyleCoverVertical
                                    defaultParams:nil
                                           isRoot:YES
                                          isModal:NO];
}

//Exposed methods previously supported
+ (instancetype)modal {
  return [self routerOptionsAsModal];
}
+ (instancetype)withPresentationStyle:(UIModalPresentationStyle)style {
  return [self routerOptionsWithPresentationStyle:style];
}
+ (instancetype)withTransitionStyle:(UIModalTransitionStyle)style {
  return [self routerOptionsWithTransitionStyle:style];
}
+ (instancetype)forDefaultParams:(NSDictionary *)defaultParams {
  return [self routerOptionsForDefaultParams:defaultParams];
}
+ (instancetype)root {
  return [self routerOptionsAsRoot];
}

//Wrappers around setters (to continue DSL-like syntax)
- (UPRouterOptions *)modal {
  [self setModal:YES];
  return self;
}
- (UPRouterOptions *)withPresentationStyle:(UIModalPresentationStyle)style {
  [self setPresentationStyle:style];
  return self;
}
- (UPRouterOptions *)withTransitionStyle:(UIModalTransitionStyle)style {
  [self setTransitionStyle:style];
  return self;
}
- (UPRouterOptions *)forDefaultParams:(NSDictionary *)defaultParams {
  [self setDefaultParams:defaultParams];
  return self;
}
- (UPRouterOptions *)root {
  [self setShouldOpenAsRootViewController:YES];
  return self;
}
@end

@interface UPRouter ()

// Map of URL format NSString -> RouterOptions
// i.e. "users/:id"
@property (readwrite, nonatomic, strong) NSMutableDictionary *routes;       // 存储注册的路由
// Map of final URL NSStrings -> RouterParams
// i.e. "users/16"
@property (readwrite, nonatomic, strong) NSMutableDictionary *cachedRoutes; // 缓存已跳转过的路由

@end

#define ROUTE_NOT_FOUND_FORMAT @"No route found for URL %@"
#define INVALID_CONTROLLER_FORMAT @"Your controller class %@ needs to implement either the static method %@ or the instance method %@"

@implementation UPRouter

- (id)init {
  if ((self = [super init])) {
    self.routes = [NSMutableDictionary dictionary];
    self.cachedRoutes = [NSMutableDictionary dictionary];
  }
  return self;
}

- (void)map:(NSString *)format toCallback:(RouterOpenCallback)callback {
  [self map:format toCallback:callback withOptions:nil];
}

- (void)map:(NSString *)format toCallback:(RouterOpenCallback)callback withOptions:(UPRouterOptions *)options {
  if (!format) {
    @throw [NSException exceptionWithName:@"RouteNotProvided"
                                   reason:@"Route #format is not initialized"
                                 userInfo:nil];
    return;
  }
  if (!options) {
    options = [UPRouterOptions routerOptions];
  }
  options.callback = callback;
  [self.routes setObject:options forKey:format];
}

- (void)map:(NSString *)format toController:(Class)controllerClass {
  [self map:format toController:controllerClass withOptions:nil];
}

- (void)map:(NSString *)format toController:(Class)controllerClass withOptions:(UPRouterOptions *)options {
  if (!format) {
    @throw [NSException exceptionWithName:@"RouteNotProvided"
                                   reason:@"Route #format is not initialized"
                                 userInfo:nil];
    return;
  }
  if (!options) {
    options = [UPRouterOptions routerOptions];
  }
  options.openClass = controllerClass;
  [self.routes setObject:options forKey:format];
}

- (void)openExternal:(NSString *)url {
  [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
}

- (void)open:(NSString *)url {
  [self open:url animated:YES];
}

- (void)open:(NSString *)url animated:(BOOL)animated {
  [self open:url animated:animated extraParams:nil];
}

- (void)open:(NSString *)url
    animated:(BOOL)animated
 extraParams:(NSDictionary *)extraParams
{
  //获取路由跳转相关的参数，往下滑动，先看怎么获取的数据，看完下面的方法再回来看这个方法
  RouterParams *params = [self routerParamsForUrl:url extraParams: extraParams];
  UPRouterOptions *options = params.routerOptions;
  
  //好了，拿到数据了，开始跳转。先判断是否有回调，如果有的话，则去执行 block
  if (options.callback) {
    RouterOpenCallback callback = options.callback;
    callback([params controllerParams]);
    return;
  }
  
  if (!self.navigationController) {
    if (_ignoresExceptions) {
      return;
    }
    
    @throw [NSException exceptionWithName:@"NavigationControllerNotProvided"
                                   reason:@"Router#navigationController has not been set to a UINavigationController instance"
                                 userInfo:nil];
  }
  
  //获取将要跳转的 VC，并且将我们传递的数据以字典的形式，传递给这个 VC
  //controllerForRouterParams 这个方法比较简单，打断点进去看看就 OK 了。
  UIViewController *controller = [self controllerForRouterParams:params];
  
  //判断当前是否有 presented 的 ViewController，有的话要 dismiss，因为接下来要跳转或者 presentViewController
  if (self.navigationController.presentedViewController) {
    [self.navigationController dismissViewControllerAnimated:animated completion:nil];
  }
  
  //是否是以模态的方式弹出 ViewController
  if ([options isModal]) {
    if ([controller.class isSubclassOfClass:UINavigationController.class]) {
      [self.navigationController presentViewController:controller
                                              animated:animated
                                            completion:nil];
    }
    else {
      UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:controller];
      navigationController.modalPresentationStyle = controller.modalPresentationStyle;
      navigationController.modalTransitionStyle = controller.modalTransitionStyle;
      [self.navigationController presentViewController:navigationController
                                              animated:animated
                                            completion:nil];
    }
  }
  else if (options.shouldOpenAsRootViewController) {
    //设置根视图
    [self.navigationController setViewControllers:@[controller] animated:animated];
  }
  else {
    [self.navigationController pushViewController:controller animated:animated];
  }
}
- (NSDictionary*)paramsOfUrl:(NSString*)url {
  return [[self routerParamsForUrl:url] controllerParams];
}

//Stack operations
- (void)popViewControllerFromRouterAnimated:(BOOL)animated {
  if (self.navigationController.presentedViewController) {
    [self.navigationController dismissViewControllerAnimated:animated completion:nil];
  }
  else {
    [self.navigationController popViewControllerAnimated:animated];
  }
}
- (void)pop {
  [self popViewControllerFromRouterAnimated:YES];
}
- (void)pop:(BOOL)animated {
  [self popViewControllerFromRouterAnimated:animated];
}

///////
- (RouterParams *)routerParamsForUrl:(NSString *)url extraParams: (NSDictionary *)extraParams {
  if (!url) {
    //if we wait, caching this as key would throw an exception
    if (_ignoresExceptions) {
      return nil;
    }
    @throw [NSException exceptionWithName:@"RouteNotFoundException"
                                   reason:[NSString stringWithFormat:ROUTE_NOT_FOUND_FORMAT, url]
                                 userInfo:nil];
  }
  
  //如果缓存中已经有了（证明之前已经跳转过这个 VC），并且传递的参数没有变化。这里需要注意了，如果传递的参数你也不确定是不是没变化，最好给 extraParams 给个值，这样就不会走缓存了否则可能传递的数据变了，但是走的还是之前的缓存。如果 VC 之间不要传递数据，不用考虑这个问题
  if ([self.cachedRoutes objectForKey:url] && !extraParams) {
    return [self.cachedRoutes objectForKey:url];
  }
  
  NSArray *givenParts = url.pathComponents;
  NSArray *legacyParts = [url componentsSeparatedByString:@"/"];
  //这里判断传入的路由路径是否正确，如果传入这样的 "iOS/app//first" 路径，则会警告。也许你的路由路径是"iOS/app"，这样写你就少传了一个实参
  if ([legacyParts count] != [givenParts count]) {
    NSLog(@"Routable Warning - your URL %@ has empty path components - this will throw an error in an upcoming release", url);
    givenParts = legacyParts;
  }
  
  __block RouterParams *openParams = nil;
  //使用枚举的方式去匹配，这里不能从 self.routes 中通过 [self.routes objectForKey:@"key"] 的方式获取，因为注册的时候，你后面添加的是参数（形参），在跳转的时候传递的是数据（实参）。这里也就是为什么需要缓存的原因了，每次跳转都要枚举这个字典，缓存了以后时间复杂度直接降到了 O(1)。
  [self.routes enumerateKeysAndObjectsUsingBlock:
   ^(NSString *routerUrl, UPRouterOptions *routerOptions, BOOL *stop) {
     //routerUrl 是枚举到的 key，也是当时注册路由时添加进去的 url，routerOptions 是枚举到的 value
       
     NSArray *routerParts = [routerUrl pathComponents];
     //判断注册的路由地址和跳转的带参数的地址是否一致，最简单的办法就是判断他们包含的元素个数是否一致，如果一致，再做更详细的判断
     if ([routerParts count] == [givenParts count]) {
       //如果个数一致，再判断是否匹配
       NSDictionary *givenParams = [self paramsForUrlComponents:givenParts routerUrlComponents:routerParts];
       if (givenParams) {
         //givenParams 存储的是路由地址中给的数据，再将 extraParams 一起传入 RouterParams，创建 RouterParams 的对象。
         openParams = [[RouterParams alloc] initWithRouterOptions:routerOptions openParams:givenParams extraParams: extraParams];
         //结束遍历
         *stop = YES;
       }
     }
   }];
  
  //如果没有匹配到路由
  if (!openParams) {
    //用户设置了忽略异常，直接返回 nil，否则会走 @throw
    if (_ignoresExceptions) {
      return nil;
    }
    @throw [NSException exceptionWithName:@"RouteNotFoundException"
                                   reason:[NSString stringWithFormat:ROUTE_NOT_FOUND_FORMAT, url]
                                 userInfo:nil];
  }
 
  //将我们辛辛苦苦封装好的路由相关的所有数据缓存起来，下次在走这个 url 的时候，直接取缓存中的数据，这就是为什么要缓存了。除非你传递的参数变了，那么一定传给 extraParams，相关方法检测到 extraParams 不为空，会重新组装数据。
  [self.cachedRoutes setObject:openParams forKey:url];
  return openParams;
}

- (RouterParams *)routerParamsForUrl:(NSString *)url {
  return [self routerParamsForUrl:url extraParams: nil];
}

//判断注册的路由和跳转的路由是否一致
- (NSDictionary *)paramsForUrlComponents:(NSArray *)givenUrlComponents
                     routerUrlComponents:(NSArray *)routerUrlComponents {
  
  __block NSMutableDictionary *params = [NSMutableDictionary dictionary];
  [routerUrlComponents enumerateObjectsUsingBlock:
   ^(NSString *routerComponent, NSUInteger idx, BOOL *stop) {
     
     NSString *givenComponent = givenUrlComponents[idx];
     //判断是否是形参，所以在注册路由时，一定要注意，参数以:开始，否则会当成路径字符串
     if ([routerComponent hasPrefix:@":"]) {
       //去除参数的:，然后将参数名作为 key，将对应的 givenComponent 作为值存入字典中，所以在调用路由的时候，传递参数（实参）顺序要一致，否则参数就错乱了
       NSString *key = [routerComponent substringFromIndex:1];
       [params setObject:givenComponent forKey:key];
     }
     else if (![routerComponent isEqualToString:givenComponent]) {
       //如果 routerComponent 不是参数名，并且路径不一致，则结束。结束后会去路由表中拿下一个路由来判断。
       params = nil;
       *stop = YES;
     }
   }];
  return params;
}

- (UIViewController *)controllerForRouterParams:(RouterParams *)params {
  SEL CONTROLLER_CLASS_SELECTOR = sel_registerName("allocWithRouterParams:");
  SEL CONTROLLER_SELECTOR = sel_registerName("initWithRouterParams:");
  UIViewController *controller = nil;
  Class controllerClass = params.routerOptions.openClass;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  if ([controllerClass respondsToSelector:CONTROLLER_CLASS_SELECTOR]) {
    controller = [controllerClass performSelector:CONTROLLER_CLASS_SELECTOR withObject:[params controllerParams]];
  }
  else if ([params.routerOptions.openClass instancesRespondToSelector:CONTROLLER_SELECTOR]) {
    controller = [[params.routerOptions.openClass alloc] performSelector:CONTROLLER_SELECTOR withObject:[params controllerParams]];
  }
#pragma clang diagnostic pop
  if (!controller) {
    if (_ignoresExceptions) {
      return controller;
    }
    @throw [NSException exceptionWithName:@"RoutableInitializerNotFound"
                                   reason:[NSString stringWithFormat:INVALID_CONTROLLER_FORMAT, NSStringFromClass(controllerClass), NSStringFromSelector(CONTROLLER_CLASS_SELECTOR),  NSStringFromSelector(CONTROLLER_SELECTOR)]
                                 userInfo:nil];
  }
  
  controller.modalTransitionStyle = params.routerOptions.transitionStyle;
  controller.modalPresentationStyle = params.routerOptions.presentationStyle;
  return controller;
}

@end

