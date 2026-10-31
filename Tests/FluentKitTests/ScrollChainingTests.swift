import XCTest
@testable import FluentKit

final class ScrollChainingTests: XCTestCase {
    private final class Parent: NSView {
        var events: [NSEvent] = []
        override func scrollWheel(with event: NSEvent) { events.append(event) }
    }
    private func scroll(x: CGFloat = 0, y: CGFloat = 0, phase: Int64 = 0,
                        momentum: Int64 = 0, time: Double) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,wheel1:Int32(y),wheel2:Int32(x),wheel3:0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous,value:1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase,value:phase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase,value:momentum)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1,value:Double(y))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2,value:Double(x))
        event.timestamp = UInt64(time*1_000_000_000)
        return NSEvent(cgEvent:event)!
    }
    @MainActor private func mount(_ child: NSView) -> Parent {
        _ = NSApplication.shared
        let parent = Parent(frame:NSRect(x:0,y:0,width:480,height:300))
        parent.addSubview(child);child.frame=NSRect(x:20,y:30,width:320,height:180);child.layoutSubtreeIfNeeded()
        return parent
    }
    private func assertSameEvents(_ actual: [NSEvent], _ expected: [NSEvent], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count,expected.count,file:file,line:line)
        for (a,b) in zip(actual,expected) { XCTAssertTrue(a === b,"Preserve original phase, timestamp and deltas",file:file,line:line) }
    }
    @MainActor func testFlipViewPassesOutwardBoundaryGestureIncludingMomentumInBothAxesAndDirections() throws {
        _ = NSApplication.shared
        for vertical in [false,true] { for rtl in [false,true] { for index in [0,2] {
            let state=FluentState(wrappedValue:index)
            let context=FluentRenderContext(reduceMotion:true,layoutDirection:rtl ? .rightToLeft:.leftToRight)
            let flip=try XCTUnwrap(FluentFlipView([0,1,2],selection:state.projectedValue,orientation:vertical ? .vertical:.horizontal) { FluentText(String($0)) }._makeView(in:context) as? FluentFlipViewHost)
            let parent=mount(flip)
            let outward:CGFloat=index==0 ? 1:-1
            func event(_ amount:CGFloat,phase:Int64=0,momentum:Int64=0,time:Double)->NSEvent {
                scroll(x:vertical ? 0:amount*(rtl ? -1:1),y:vertical ? amount:0,phase:phase,momentum:momentum,time:time)
            }
            let events=[event(outward,phase:1,time:1),event(outward*40,phase:2,time:1.01),event(0,phase:4,time:1.02),
                        event(outward*12,momentum:1,time:1.03),event(0,momentum:3,time:1.04)]
            events.forEach { flip.scrollWheel(with:$0) }
            assertSameEvents(parent.events,events)
            XCTAssertEqual(state.wrappedValue,index);XCTAssertFalse(flip.isPanning);XCTAssertEqual(flip.panOffset,0)
        }}}
    }
    @MainActor func testCrossAxisHandoffKeepsTheInitialSmallEventForEverySharedPanControl() throws {
        _ = NSApplication.shared
        let flip=FluentFlipView([0,1]) { FluentText(String($0)) }._makeView(in:.init(reduceMotion:true))
        let pivot=FluentPivot(["A","B"],header:{$0}) { FluentText($0) }._makeView(in:.init(reduceMotion:true))
        let swipe=FluentSwipeControl(rightItems:FluentSwipeItems(mode:.reveal,[FluentSwipeItem("Archive") {}])) { FluentText("Message") }._makeView(in:.init(reduceMotion:true))
        for child in [flip,pivot,swipe] {
            let parent=mount(child)
            let events=[scroll(y:1,phase:1,time:1),scroll(y:12,phase:2,time:1.01),scroll(phase:4,time:1.02)]
            events.forEach { child.scrollWheel(with:$0) }
            assertSameEvents(parent.events,events)
        }
    }
    @MainActor func testSubthresholdGestureIsReturnedInFullWhenItEnds() {
        _ = NSApplication.shared
        let flip=FluentFlipView([0,1]) { FluentText(String($0)) }._makeView(in:.init(reduceMotion:true))
        let parent=mount(flip)
        let events=[scroll(x:1,phase:1,time:1),scroll(x:-1,phase:2,time:1.01),scroll(phase:4,time:1.02)]
        events.forEach { flip.scrollWheel(with:$0) }
        assertSameEvents(parent.events,events)
    }
    @MainActor func testInwardPagingKeepsWholeGestureAndMomentumWithoutLeakingToParent() throws {
        _ = NSApplication.shared
        for vertical in [false,true] { for rtl in [false,true] { for index in [0,2] {
            let state=FluentState(wrappedValue:index)
            var changes:[Int]=[]
            let context=FluentRenderContext(reduceMotion:true,layoutDirection:rtl ? .rightToLeft:.leftToRight)
            let flip=try XCTUnwrap(FluentFlipView([0,1,2],selection:state.projectedValue,orientation:vertical ? .vertical:.horizontal,
                onSelectionChanged:{ changes.append($0) }) { FluentText(String($0)) }._makeView(in:context) as? FluentFlipViewHost)
            let parent=mount(flip)
            let inward:CGFloat=index==0 ? -1:1
            func event(_ amount:CGFloat,phase:Int64=0,momentum:Int64=0,time:Double)->NSEvent {
                scroll(x:vertical ? 0:amount*(rtl ? -1:1),y:vertical ? amount:0,phase:phase,momentum:momentum,time:time)
            }
            let events=[event(inward,phase:1,time:1),event(inward*250,phase:2,time:1.01),event(0,phase:4,time:2),
                        event(inward*12,momentum:1,time:2.01),event(0,momentum:3,time:2.02)]
            events.forEach { flip.scrollWheel(with:$0) }
            XCTAssertTrue(parent.events.isEmpty);XCTAssertEqual(state.wrappedValue,1);XCTAssertEqual(changes,[1])
        }}}
    }
    @MainActor func testNestedPagersAcquireHandedOffSequenceWithItsBeginning() throws {
        _ = NSApplication.shared
        let innerState=FluentState(wrappedValue:0), outerState=FluentState(wrappedValue:1)
        let context=FluentRenderContext(reduceMotion:true)
        let inner=FluentFlipView([0,1],selection:innerState.projectedValue) { FluentText(String($0)) }._makeView(in:context)
        let outer=try XCTUnwrap(FluentFlipView([0,1,2],selection:outerState.projectedValue) { id in
            FluentNativeView(make:{ id==1 ? inner:NSView() },update:{ (_:NSView,_) in })
        }._makeView(in:context) as? FluentFlipViewHost)
        let parent=mount(outer)
        XCTAssertGreaterThan(inner.bounds.width,0)
        inner.scrollWheel(with:scroll(x:1,phase:1,time:1))
        inner.scrollWheel(with:scroll(x:220,phase:2,time:1.01))
        XCTAssertTrue(outer.isPanning);XCTAssertEqual(outer.panOffset,221)
        inner.scrollWheel(with:scroll(phase:4,time:2))
        XCTAssertEqual(innerState.wrappedValue,0);XCTAssertEqual(outerState.wrappedValue,0)
        XCTAssertTrue(parent.events.isEmpty)
    }
    @MainActor func testJitterBufferIsBoundedAndForwardsWithoutLosingAnyEvent() {
        _ = NSApplication.shared
        let flip=FluentFlipView([0,1]) { FluentText(String($0)) }._makeView(in:.init(reduceMotion:true))
        let parent=mount(flip)
        var sent:[NSEvent]=[]
        for i in 0..<1000 {
            let event=scroll(x:i%2==0 ? 1:-1,phase:i==0 ? 1:2,time:Double(i)/1000)
            sent.append(event);flip.scrollWheel(with:event)
            if i==31 { XCTAssertTrue(parent.events.isEmpty) }
            if i==32 { XCTAssertEqual(parent.events.count,33,"Undecided history must not grow indefinitely") }
        }
        let end=scroll(phase:4,time:2);sent.append(end);flip.scrollWheel(with:end)
        assertSameEvents(parent.events,sent)
    }
    @MainActor func testTentativeCancellationAndDeniedBeginDoNotLoseGestureHistory() {
        _ = NSApplication.shared
        let driver=FluentPanGestureDriver(view:NSView(),axis:.horizontal)
        var began=0,changed=0,ended=0,cancelled=0
        driver.onBegin={ began+=1;return 0 };driver.onChange={ _ in changed+=1 }
        driver.onEnd={ _ in ended+=1 };driver.onCancel={ cancelled+=1 }
        var forwarded:[NSEvent]=[]
        func send(_ event:NSEvent) {
            if !driver.handleScrollWheel(event,replayUnclaimed:{ forwarded.append($0) }) { forwarded.append(event) }
        }
        let small=[scroll(x:1,phase:1,time:1),scroll(phase:8,time:1.01)]
        small.forEach(send);assertSameEvents(forwarded,small)
        XCTAssertEqual(began+changed+ended+cancelled,0)
        forwarded=[];driver.onBeginAllowed={ false }
        let denied=[scroll(x:1,phase:1,time:2),scroll(x:20,phase:2,time:2.01),scroll(phase:4,time:2.02)]
        denied.forEach(send);assertSameEvents(forwarded,denied)
        XCTAssertEqual(began+changed+ended+cancelled,0)
        driver.detach()
    }
    @MainActor func testDirectionPolicyAllowsRegrabbingVisiblePartialPageThenRestoresBoundary() throws {
        _ = NSApplication.shared
        let flip=try XCTUnwrap(FluentFlipView([0,1]) { FluentText(String($0)) }._makeView(in:.init(reduceMotion:true)) as? FluentFlipViewHost)
        let parent=mount(flip)
        XCTAssertFalse(flip.allowsInteractivePan(toward:1));XCTAssertTrue(flip.allowsInteractivePan(toward:-1))
        XCTAssertNotNil(flip.beginInteractivePan());flip.updateInteractivePan(translation:-30)
        XCTAssertTrue(flip.allowsInteractivePan(toward:1),"The previous partial page can be pulled back")
        flip.endInteractivePan(velocity:0)
        XCTAssertFalse(flip.allowsInteractivePan(toward:1));XCTAssertTrue(parent.events.isEmpty)
    }

}
