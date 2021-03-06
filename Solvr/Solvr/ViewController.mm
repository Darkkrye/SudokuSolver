//
//  ViewController.m
//  Solvr
//
//  Created by Chris Lewis on 20/10/14.
//  Copyright (c) 2014 Chris Lewis. All rights reserved.
//

#import "ViewController.h"
#import <string>
#import <TesseractOCR/TesseractOCR.h>
#import "ComputerVision.h"
#import "NorvigSolver.h"
#import "EricaSadanCookbook.h"

@interface ViewController() <ARSCNViewDelegate>

@end

@implementation ViewController

BOOL usingSampleImage = NO;
ComputerVision* cv = NULL;
NSString* empty_board = @"000000000000000000000000000000000000000000000000000000000000000000000000000000000";

// Track webview load status and inputs waiting to be sent
BOOL boardLoaded = NO;
NSString* boardToShow = @"";
NSString* solutionForBoard = @"";

- (void) viewDidLoad {
    [super viewDidLoad];
    [self becomeFirstResponder];
    
    // Board Detection
    cv = [[ComputerVision alloc] init];
    
    // Results Board
    NSLog( @"Load HTML Board" );
    self.board.hidden = YES;
    self.board.delegate = self;
    boardLoaded = NO;
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"board" withExtension:@"html"];
    [self.board loadRequest:[NSURLRequest requestWithURL:url]];
    
    // AVCapture
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPresetMedium;
    
    // Find camera
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if( input ) {
        [session addInput:input];
        
        self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
        NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys: AVVideoCodecJPEG, AVVideoCodecKey, nil];
        [self.stillImageOutput setOutputSettings:outputSettings];
        
        [session addOutput:self.stillImageOutput];
        [session startRunning];
        
        self.captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
        self.captureVideoPreviewLayer.frame = self.view.frame;
        [self.captureVideoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
        [self.backgroundImage.layer addSublayer:self.captureVideoPreviewLayer];
    } else {
        NSLog( @"ERROR: trying to open camera: %@", error );
        [self showFeedback:@"Camera not found, using sample image instead." withDuration:0];
        self.backgroundImage.image = [UIImage imageNamed:@"SampleImage"];
        usingSampleImage = YES;
    }
    
    self.akSceneView.delegate = self;
    self.akSceneView.frame = CGRectMake(0.0, 0.0, self.view.bounds.size.width, self.view.bounds.size.height);
}

- (void) didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
//    ARConfiguration* configuration = [[ARWorldTrackingConfiguration alloc] init];
//    [self.akSceneView.session runWithConfiguration:configuration];
}

// Results Board Webview

- (void) webViewDidFinishLoad:(UIWebView*)webView {
    boardLoaded = YES; // one would expect this to be covered by `webView.loading`
    if( ![boardToShow isEqualToString:@""] ) {
        [self update:boardToShow withSolution:solutionForBoard];
    }
}

- (void) update:(NSString*)board withSolution:(NSString*)solution {
    // passing the empty board to update will hide the current board if it's visible
    if( [board isEqualToString:empty_board] && !self.board.hidden ) {
        self.board.hidden = YES;
        [UIView animateWithDuration:0.3 animations:^(void) {
            self.board.alpha = 0;
        }];
    } else {
        boardToShow = board;
        solutionForBoard = solution;
        NSLog( @"%@ \n \n %@", boardToShow, solutionForBoard );

        if( boardLoaded ) {
            // heights of button/feedback label are variable
            self.boardSpacing.constant = ( self.view.frame.size.height - self.feedback.frame.origin.y ) / 2;
            NSLog( @"%f", self.view.frame.size.height - self.feedback.frame.origin.y );
            [self.board setNeedsLayout];
            
            NSString* js = [[NSString alloc] initWithFormat:@"set_board('%@', '%@' );", boardToShow, solutionForBoard];
            [self.board stringByEvaluatingJavaScriptFromString:js];
            self.board.hidden = NO;
            self.board.alpha = 0;
            
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                UIImage* image = [self captureWebView:self.board];
                [self.imageV setImage:image];
                [self.imageV setHidden:YES];
                
                [self showFeedback:@"OK ! Cliquez pour faire apparaître la solution" withDuration:2.0];
            });
            
            /*[UIView animateWithDuration:0.3 animations:^(void) {
                self.board.alpha = 1;
            }];*/
        }
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    ARWorldTrackingConfiguration* configuration = [[ARWorldTrackingConfiguration alloc] init];
    configuration.planeDetection = ARPlaneAnchorAlignmentHorizontal;
    [self.akSceneView.session runWithConfiguration:configuration];
    
    UITouch* touch = touches.allObjects.firstObject;
    NSArray<ARHitTestResult*>* results = [self.akSceneView hitTest:[touch locationInView:self.akSceneView] types:ARHitTestResultTypeFeaturePoint];
    ARHitTestResult *result = results.firstObject;
    matrix_float4x4 transform = result.worldTransform;
    SCNMatrix4 matrix = SCNMatrix4FromMat4(transform);
    SCNVector3 position = SCNVector3Make(matrix.m41, matrix.m42, matrix.m43);
    
    [self.akSceneView.scene.rootNode addChildNode:[self createNodeAt:position]];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self.backgroundImage setHidden:YES];
    });
}

- (SCNNode*) createNodeAt:(SCNVector3)position {
    SCNPlane* geometry = [[SCNPlane alloc] init];
    geometry.width = 0.025;
    geometry.height = 0.025;
    
    SCNMaterial* material = [[SCNMaterial alloc] init];
    material.diffuse.contents = self.imageV.image;
    
    geometry.firstMaterial = material;
    
    SCNNode* node = [[SCNNode alloc] init];
    node.geometry = geometry;
    node.position = position;
    
    return node;
}

- (UIImage*) captureWebView: (UIWebView*)webView {
    // capture webview
    UIImage *img = nil;
    UIGraphicsBeginImageContextWithOptions(webView.scrollView.contentSize, webView.scrollView.opaque, 0.0);
    {
        CGPoint savedContentOffset = webView.scrollView.contentOffset;
        CGRect savedFrame = webView.scrollView.frame;
        
        webView.scrollView.contentOffset = CGPointZero;
        webView.scrollView.frame = CGRectMake(0, 0, webView.scrollView.contentSize.width, webView.scrollView.contentSize.height);
        [webView.scrollView.layer renderInContext: UIGraphicsGetCurrentContext()];
        img = UIGraphicsGetImageFromCurrentImageContext();
        
        webView.scrollView.contentOffset = savedContentOffset;
        webView.scrollView.frame = savedFrame;
    }
    UIGraphicsEndImageContext();
    return img;
}

// Omnibutton Press

- (IBAction) captureNow:(id)sender {
    // when board is visible, override default functionality and clear
    if( self.board.hidden == NO ) {
        [self.omnibutton setTitle:@"Press to Solve" forState:UIControlStateNormal];
        [self update:empty_board withSolution:empty_board];
        [self.backgroundImage setHidden:NO];
        for (SCNNode* node in self.akSceneView.scene.rootNode.childNodes) {
            [node removeFromParentNode];
        }
        [self.akSceneView.session pause];
        return;
    }

    // disable button to avoid mashing
    self.omnibutton.enabled = NO;

    if( usingSampleImage ) {
        [self processImage:self.backgroundImage.image];
    } else { // capture frame from camera
        AVCaptureConnection *videoConnection = [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
        [videoConnection setVideoOrientation:AVCaptureVideoOrientationPortrait];

        [self.stillImageOutput
         captureStillImageAsynchronouslyFromConnection:videoConnection
         completionHandler:^( CMSampleBufferRef imageDataSampleBuffer, NSError *error ) {
             if( error ) { // todo: better error
                 NSLog( @"error (lol this is super helpful isn't it.)" );
             } else {
                 NSData *jpegData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                 UIImage *image = [UIImage imageWithData:jpegData];
                 image = applyAspectFillImage( image, self.captureVideoPreviewLayer.frame );
                 [self processImage:image];
             }
         }
         ];
    }
}

- (void) processImage:(UIImage*)image {
    // Tesseract is initialised here due to an ongoing bug where doing so in
    // global scope leads to bizzare misreads after second image. This does
    // harm performance due to wasted cycles re-initialising but the hit
    // doesn't appear to be noticable.
    Tesseract* tesseract = [[Tesseract alloc] initWithLanguage:@"eng"];
    [tesseract setVariableValue:@"123456789" forKey:@"tessedit_char_whitelist"]; // only numbers
    [tesseract setVariableValue:@"7" forKey:@"tessedit_pageseg_mode"]; // one character per image
    
    NSString* flat_board = [cv recogniseSudokuFromImage:image withOCR:tesseract];
    
    // McGuire, Tugemann, Gilles and Civario proved that a board featuring 16 or fewer clues lacks a unique solution (http://arxiv.org/abs/1201.0749)
    NSRegularExpression* validPuzzle = [NSRegularExpression regularExpressionWithPattern:@"[1-9]" options:NSRegularExpressionCaseInsensitive error:nil];
    NSArray* matches = [validPuzzle matchesInString:flat_board options:0 range:NSMakeRange(0, [flat_board length])];

    if( [flat_board isEqualToString:empty_board] ) {
        [self showFeedback:@"Sorry! I couldn't find the board :(" withDuration:5.0];
    } else if( [matches count] <= 16 ) {
        [self showFeedback:@"Sorry! The puzzle did not have a unique solution :(" withDuration:5.0];
    } else {
        // convert to c++ string and feed to solver
        Sudoku::init();
        auto sc = new Sudoku( std::string( [flat_board UTF8String] ) );
        
        // contradiction detected in puzzle
        if( sc->valid ) {
            if( auto S = solve( std::unique_ptr<Sudoku>( sc ) ) ) {
                [self update:flat_board withSolution:[NSString stringWithUTF8String:S->flatten().c_str()]];
                [self.omnibutton setTitle:@"Clear" forState:UIControlStateNormal];

            } else {
                [self showFeedback:@"Sorry! I couldn't find the board :(" withDuration:5.0];
            }
        } else {
            [self showFeedback:@"Unable to solve. The puzzle contained a contradiction :(" withDuration:5.0];
            [self update:empty_board withSolution:flat_board];
            [self.omnibutton setTitle:@"Clear" forState:UIControlStateNormal];
        }
    }

    self.omnibutton.enabled = YES; // e-enable button if disabled
}

// Handle user feedback label
- (void) showFeedback:(NSString*)message withDuration:(float)duration {
    self.feedback.text = message;
    if( self.feedback.hidden ) {
        // unhide but maintain 0 alpha for fade-in effect
        self.feedback.hidden = NO;
        self.feedback.alpha = 0;

        // modify autolayout to accomodate the translation
        int distance = self.feedback.layer.frame.size.height;
        self.feedbackSpacing.constant = distance;
        [self.feedback layoutIfNeeded];
        
        [UIView animateWithDuration:0.6
                         animations:^(void){
                             self.feedback.transform = CGAffineTransformMakeTranslation(0, distance);
                             self.feedback.alpha = 1;
                         }
                         completion:^(BOOL finished) {
                             // fade-out if non-zero duration specified
                             if( duration ) {
                                 [UIView animateWithDuration:0.6
                                                       delay:2.0
                                                     options:UIViewAnimationOptionCurveEaseInOut
                                                  animations:^(void) {
                                                      self.feedback.transform = CGAffineTransformMakeTranslation(0, 0);
                                                      self.feedback.alpha = 0;
                                                  }
                                                  completion:^(BOOL finished) {
                                                      self.feedback.hidden = YES;
                                                  }
                                  ];
                             }
                         }
         ];
    }
}

// Shake to view example image
- (void) motionEnded:(UIEventSubtype)motion withEvent:(UIEvent*)event {
    if( event.subtype == UIEventSubtypeMotionShake ) {
        if( usingSampleImage ) {
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Solvr" message:@"Do you want to hide the sample image?" preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                NSLog( @"Cancel" );
            }];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^   (UIAlertAction *action) {
                usingSampleImage = NO;
                self.captureVideoPreviewLayer.hidden = NO;
                self.backgroundImage.image = nil;
            }];
            [alert addAction:cancelAction];
            [alert addAction:okAction];
            [self presentViewController:alert animated:YES completion:nil];
        } else {
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Solvr" message:@"Do you want to load a sample image?" preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                NSLog( @"Cancel" );
            }];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                usingSampleImage = YES;
                self.captureVideoPreviewLayer.hidden = YES;
                self.backgroundImage.image = [UIImage imageNamed:@"SampleImage"];
            }];
            [alert addAction:cancelAction];
            [alert addAction:okAction];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
    
    if ( [super respondsToSelector:@selector(motionEnded:withEvent:)] ) {
        [super motionEnded:motion withEvent:event];
    }
}

@end
