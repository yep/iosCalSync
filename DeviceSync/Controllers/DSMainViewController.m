//
//  DSMainViewController.m
//  DeviceSync
//
// Copyright (c) 2013 Jahn Bertsch
// Copyright (c) 2012 Rasmus Andersson <http://rsms.me/>
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
//

#import <EventKit/EventKit.h>
#import "RESideMenu.h"
#import "DSMainViewController.h"
#import "DSProtocol.h"
#import "DSChannelDelegate.h"
#import "EKEvent+NSCoder.h"

@interface DSMainViewController ()
@end

@implementation DSMainViewController

- (void)awakeFromNib
{
    DLog(@"awakeFromNib %p", self);
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.outputTextView.text = @"";
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc
{
    DLog(@"dealloc %p", self);
}

- (void)displayMessage:(NSString *)message
{
    DLog(@">> %@", message);
    NSString *text = self.outputTextView.text;

    if (text.length == 0) {
        self.outputTextView.text = [text stringByAppendingString:message];
    } else {
        self.outputTextView.text = [text stringByAppendingFormat:@"\n%@\n", message];
        [self.outputTextView scrollRangeToVisible:NSMakeRange(self.outputTextView.text.length, 0)];
    }
}

- (IBAction)syncButtonPressed:(id)sender
{
    if (!self.channelDelegate.connected) {
        [self displayMessage:@"Can not synchronize calendar: No USB connection."];
        [self displayMessage:@"Is the USB cable plugged in and is 'DeviceSync for OS X' running on your computer?"];
    } else {
        [self displayMessage:@"Starting calendar synchronization."];
        [self askForCalendarPermissions];
    }
}

- (IBAction)menuButtonPressed:(id)sender
{
    [self.sideMenuViewController presentMenuViewController];
}

#pragma mark - calendar

- (void)askForCalendarPermissions
{
    EKEventStore *eventStore = [[EKEventStore alloc] init];
    __block BOOL accessGranted = NO;

    if ([eventStore respondsToSelector:@selector(requestAccessToEntityType:completion:)]) {
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [eventStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error) {
            accessGranted = granted;
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    } else {
        // ios 5 or older
        accessGranted = YES;
    }

    if (!accessGranted) {
        [self displayMessage:@"No permissions to access calendar. Please enable calendar access in iOS settings."];
    } else {
        if (self.channelDelegate.peerChannel) {
            [self exportEventStore:eventStore];
        } else {
            [self displayMessage:@"Can't export data. Not connected"];
        }
    }
}

- (void)exportEventStore:(EKEventStore *)eventStore
{
    NSArray *calendars = [eventStore calendarsForEntityType:EKEntityTypeEvent];

    for (EKCalendar *calendar in calendars) {
        [self sendCalendar:calendar];

        [self displayMessage:[NSString stringWithFormat:@"Exporting calendar with title '%@'.", calendar.title]];

        NSDate *endDate = [NSDate dateWithTimeIntervalSinceNow:[[NSDate distantFuture] timeIntervalSinceReferenceDate]];
        NSArray *calendarArray = [NSArray arrayWithObject:calendar];
        NSPredicate *fetchCalendarEvents = [eventStore predicateForEventsWithStartDate:[NSDate date] endDate:endDate calendars:calendarArray];
        NSArray *eventList = [eventStore eventsMatchingPredicate:fetchCalendarEvents];

        [self displayMessage:[NSString stringWithFormat:@"Found %lu calendar events.", (unsigned long)eventList.count]];

        for (int i = 0; i < eventList.count; i++) {
            [self sendEvent:[eventList objectAtIndex:i]];

            if (i == 99) {
                [self displayMessage:[NSString stringWithFormat:@"Only exporting first 100 events."]];
                break;
            }
        }
    }
}

#pragma mark - communication

- (void)sendCalendar:(EKCalendar *)calendar
{
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:calendar.title, @"title",
                          nil];
    dispatch_data_t payload = [info createReferencingDispatchData];

    [self.channelDelegate.peerChannel sendFrameOfType:DSDeviceSyncFrameTypeCalendar tag:PTFrameNoTag withPayload:payload callback:^(NSError *error) {
        if (error) {
            NSLog(@"Failed to send DSDeviceSyncFrameTypeCalendar: %@", error);
        }
    }];
}

- (void)sendEvent:(EKEvent *)event
{
    NSData *eventData = [NSKeyedArchiver archivedDataWithRootObject:event];
    dispatch_data_t payload = DSDeviceSyncDispatchData(eventData);

    [self.channelDelegate.peerChannel sendFrameOfType:DSDeviceSyncFrameTypeEvent tag:PTFrameNoTag withPayload:payload callback:^(NSError *error) {
        if (error) {
            NSLog(@"Failed to send event: %@", error);
        }
    }];

    [self displayMessage:[NSString stringWithFormat:@"Sending event '%@'", event.title]];
}


@end
