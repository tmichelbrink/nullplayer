import Foundation
import XCTest
@testable import NullPlayer

/// The FastScript interpreter on synthetic programs, written as the syntax tree AIMP compiles
/// (`.fsxml`, `reference/format.md` § *Scripts*), run against a one-form skin built in memory.
@MainActor
final class AIMPSkinScriptTests: XCTestCase {
    // MARK: - Declarations

    /// `var X: T = value` starts at its value, and a parameter left out takes its default.
    func testInitializersAndParameterDefaults() throws {
        let engine = try Self.run("""
        <program>
          <function><name text="Tries"/>
            <parameters><var><ident text="Name"/><type text="String"/></var>
              <var><ident text="Count"/><type text="Integer"/><init><expr><number text="5"/></expr></init></var></parameters>
            <compoundstmt><assignstmt><dsgn><node text="Result"/></dsgn><expr><dsgn><node text="Count"/></dsgn></expr></assignstmt></compoundstmt>
          </function>
          <procedure><name text="Execute"/>
            <var><ident text="Normalize"/><type text="Boolean"/><init><expr><dsgn><node text="True"/></dsgn></expr></init></var>
            <var><ident text="Plain"/><type text="Integer"/></var>
            <compoundstmt>
              <assignstmt><dsgn><node text="Defaulted"/></dsgn>
                <expr><dsgn><node text="Tries"/><expr><string text="'a'"/></expr></dsgn></expr></assignstmt>
              <assignstmt><dsgn><node text="Given"/></dsgn>
                <expr><dsgn><node text="Tries"/><expr><string text="'a'"/></expr><expr><number text="2"/></expr></dsgn></expr></assignstmt>
              <assignstmt><dsgn><node text="Seen"/></dsgn>
                <expr><dsgn><node text="Normalize"/></dsgn><op text="+"/><dsgn><node text="Plain"/></dsgn></expr></assignstmt>
            </compoundstmt>
          </procedure>
        </program>
        """)
        XCTAssertEqual(engine.state.script.variables["defaulted"], "5")
        XCTAssertEqual(engine.state.script.variables["given"], "2")
        XCTAssertEqual(engine.state.script.variables["seen"], "1", "True plus an uninitialised Integer")
    }

    /// Operators bind as Pascal's do, left to right within a level, a unary one to the operand after it.
    func testExpressionsCompileByPrecedence() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <assignstmt><dsgn><node text="Seen"/></dsgn>
            <expr><number text="10"/><op text="-"/><number text="2"/><op text="*"/><number text="3"/><op text="-"/>
              <op text="unminus"/><number text="1"/></expr></assignstmt>
          <assignstmt><dsgn><node text="Given"/></dsgn>
            <expr><op text="not"/><number text="0"/><op text="="/><number text="1"/></expr></assignstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.variables["seen"], "5", "10 - 2 * 3 - -1")
        XCTAssertEqual(engine.state.script.variables["given"], "1", "(not 0) = 1")
    }

    /// A tree the compiler does not take is a load-time finding, not a run that stops.
    func testAMalformedTreeDoesNotCompile() throws {
        let unknown = try Self.node("<program><compoundstmt><gotostmt/></compoundstmt></program>")
        XCTAssertThrowsError(try AIMPSkinScript.compile(unknown))
        let dangling = try Self.node("""
        <program><compoundstmt><assignstmt><dsgn><node text="X"/></dsgn><expr><number text="1"/><op text="+"/></expr></assignstmt>
        </compoundstmt></program>
        """)
        XCTAssertThrowsError(try AIMPSkinScript.compile(dangling))
    }

    // MARK: - Entry points

    /// A counter's script gets its state as its `var` parameter, whatever the parameter is called,
    /// and what the script leaves there is the counter's new position.
    func testACounterStateParameterMayHaveAnyName() throws {
        let program = try AIMPSkinScript.compile(Self.node("""
        <program><procedure><name text="Execute"/>
          <parameters><varparams/><var><ident text="ALayout"/><type text="Integer"/></var></parameters>
          <compoundstmt><assignstmt><dsgn><node text="ALayout"/></dsgn>
            <expr><dsgn><node text="ALayout"/></dsgn><op text="+"/><number text="1"/></expr></assignstmt></compoundstmt>
        </procedure></program>
        """))
        XCTAssertEqual(try Self.engine().run(program, statePosition: 2), 3)
    }

    /// The counter's position binds its `State` parameter even where the schema declares a variable
    /// of the same name: the variable does not stand in for the position.
    func testACounterStateParameterShadowsASchemaVariable() throws {
        let program = try AIMPSkinScript.compile(Self.node("""
        <program><procedure><name text="Execute"/>
          <parameters><varparams/><var><ident text="Seen"/><type text="Integer"/></var></parameters>
          <compoundstmt><assignstmt><dsgn><node text="Seen"/></dsgn>
            <expr><dsgn><node text="Seen"/></dsgn><op text="+"/><number text="1"/></expr></assignstmt></compoundstmt>
        </procedure></program>
        """))
        XCTAssertEqual(try Self.engine().run(program, statePosition: 4), 5)
    }

    /// A routine's `var` parameter writes its last value back to the variable passed for it; a value
    /// parameter does not.
    func testAVarParameterWritesBack() throws {
        let engine = try Self.run("""
        <program>
          <procedure><name text="Bump"/>
            <parameters><varparams/><var><ident text="N"/><type text="Integer"/></var></parameters>
            <compoundstmt><assignstmt><dsgn><node text="N"/></dsgn>
              <expr><dsgn><node text="N"/></dsgn><op text="+"/><number text="1"/></expr></assignstmt></compoundstmt>
          </procedure>
          <procedure><name text="Copy"/>
            <parameters><var><ident text="N"/><type text="Integer"/></var></parameters>
            <compoundstmt><assignstmt><dsgn><node text="N"/></dsgn><expr><number text="9"/></expr></assignstmt></compoundstmt>
          </procedure>
          <procedure><name text="Execute"/><compoundstmt>
            <assignstmt><dsgn><node text="Given"/></dsgn><expr><number text="2"/></expr></assignstmt>
            <callstmt><dsgn><node text="Bump"/><expr><dsgn><node text="Given"/></dsgn></expr></dsgn></callstmt>
            <assignstmt><dsgn><node text="Seen"/></dsgn><expr><number text="4"/></expr></assignstmt>
            <callstmt><dsgn><node text="Copy"/><expr><dsgn><node text="Seen"/></dsgn></expr></dsgn></callstmt>
          </compoundstmt></procedure>
        </program>
        """)
        XCTAssertEqual(engine.state.script.variables["given"], "3")
        XCTAssertEqual(engine.state.script.variables["seen"], "4")
    }

    /// A `var` parameter's write survives a routine that then raises: the caller's `except` sees it.
    func testAVarParameterWriteSurvivesARaise() throws {
        let engine = try Self.run("""
        <program>
          <procedure><name text="Change"/>
            <parameters><varparams/><var><ident text="N"/><type text="Integer"/></var></parameters>
            <compoundstmt>
              <assignstmt><dsgn><node text="N"/></dsgn><expr><number text="3"/></expr></assignstmt>
              <assignstmt><dsgn><node text="N"/></dsgn><expr><number text="1"/><op text="div"/><number text="0"/></expr></assignstmt>
            </compoundstmt>
          </procedure>
          <procedure><name text="Execute"/><compoundstmt>
            <assignstmt><dsgn><node text="Given"/></dsgn><expr><number text="1"/></expr></assignstmt>
            <trystmt>
              <callstmt><dsgn><node text="Change"/><expr><dsgn><node text="Given"/></dsgn></expr></dsgn></callstmt>
              <exceptstmt><assignstmt><dsgn><node text="Seen"/></dsgn><expr><number text="1"/></expr></assignstmt></exceptstmt>
            </trystmt>
          </compoundstmt></procedure>
        </program>
        """)
        XCTAssertEqual(engine.state.script.variables["seen"], "1", "the raise was caught")
        XCTAssertEqual(engine.state.script.variables["given"], "3", "the write before it stands")
    }

    /// A negative precision is none, not a crash: `Format('%.-1s', ['abc'])` is `abc`.
    func testANegativeFormatPrecisionIsNone() throws {
        XCTAssertEqual(try AIMPSkinScript.format("%.-1s", .string("abc")), "abc")
    }

    /// Delphi's clock is the local civil time: 03:00 local is an eighth of the local day, whatever the
    /// time zone.
    func testTheDelphiClockReadsLocalCivilTime() throws {
        let local = try XCTUnwrap(DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 11, day: 24, hour: 3).date)
        let value = AIMPSkinScript.Builtin.dateTime(local)
        XCTAssertEqual(value - value.rounded(.down), 0.125, accuracy: 0.000_01)
        XCTAssertEqual(value.rounded(.down), 46_350, "2026-11-24 is day 46,350 from 1899-12-30")
        XCTAssertEqual(AIMPSkinScript.Builtin.date(value).timeIntervalSince(local), 0, accuracy: 0.01)
    }

    /// A unit with no `Execute` runs its own `begin … end.` block and finishes.
    func testAProgramWithoutExecuteRunsItsBlock() throws {
        let engine = try Self.run("""
        <program><compoundstmt>
          <assignstmt><dsgn><node text="Seen"/></dsgn><expr><number text="1"/></expr></assignstmt>
        </compoundstmt><types/></program>
        """)
        XCTAssertEqual(engine.state.script.variables["seen"], "1")
    }

    /// A skin's `except` does not hide what the interpreter cannot do: the run stops, after its
    /// `finally`, and the gap shows.
    func testUnsupportedPassesThroughExcept() throws {
        let program = try AIMPSkinScript.compile(Self.node("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <trystmt>
            <callstmt><dsgn><node text="NoSuchCall"/></dsgn></callstmt>
            <exceptstmt><assignstmt><dsgn><node text="Given"/></dsgn><expr><number text="1"/></expr></assignstmt></exceptstmt>
            <finallystmt><assignstmt><dsgn><node text="Seen"/></dsgn><expr><number text="1"/></expr></assignstmt></finallystmt>
          </trystmt>
        </compoundstmt></procedure></program>
        """))
        let engine = try Self.engine()
        XCTAssertThrowsError(try engine.run(program)) { XCTAssertTrue($0 is AIMPSkinScript.Unsupported) }
        XCTAssertEqual(engine.state.script.variables["seen"], "1", "the cleanup ran")
        XCTAssertNil(engine.state.script.variables["given"], "the handler did not")
    }

    // MARK: - Operators

    /// Script arithmetic answers as a binding's `Expression` does: one operator core
    /// (`AIMPSkinExpression.Operator.apply`). `and`, `or`, `xor` are bitwise on whole numbers, as
    /// Pascal's on integers, and so logical on 0 and 1.
    func testOperatorsAnswerAsBindingsDo() throws {
        let cases: [(Double, String, Double)] = [
            (6, "xor", 3), (6, "and", 3), (4, "or", 1), (1, "xor", 1), (1, "and", 0), (7, "div", 2), (7, "mod", 3),
            (-7, "mod", 3), (7, "/", 2), (1, "shl", 3), (16, "shr", 2), (2, "=", 2), (2, "<>", 3), (2, "<=", 1),
        ]
        for (left, op, right) in cases {
            let engine = try Self.run("""
            <program><procedure><name text="Execute"/><compoundstmt>
              <assignstmt><dsgn><node text="Seen"/></dsgn>
                <expr><number text="\(left)"/><op text="\(op.replacingOccurrences(of: "<", with: "&lt;"))"/><number text="\(right)"/></expr></assignstmt>
            </compoundstmt></procedure></program>
            """)
            let binding = try XCTUnwrap(AIMPSkinExpression("value1 \(op) value2")?.evaluate(variables: ["value1": left, "value2": right]))
            XCTAssertEqual(engine.state.script.variables["seen"], AIMPSkinScript.Value.number(binding).string, "\(left) \(op) \(right)")
        }
        XCTAssertEqual(AIMPSkinExpression("6 and 3")?.evaluate(value: 0), 2, "bitwise, not logical")
    }

    /// A zero divisor raises, as Delphi's `EDivByZero` does: the skin's `except` catches it, and the
    /// assignment it stopped does not happen. Uncaught, it ends the run, keeping what ran before it.
    /// A binding's expression gives nil (`AIMPSkinModelTests`).
    func testDivisionByZeroRaisesWhatExceptCatches() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <trystmt>
            <assignstmt><dsgn><node text="Seen"/></dsgn><expr><number text="1"/><op text="div"/><number text="0"/></expr></assignstmt>
            <exceptstmt><assignstmt><dsgn><node text="Given"/></dsgn><expr><number text="1"/></expr></assignstmt></exceptstmt>
          </trystmt>
          <assignstmt><dsgn><node text="Defaulted"/></dsgn><expr><number text="1"/></expr></assignstmt>
          <assignstmt><dsgn><node text="Where"/></dsgn><expr><number text="0"/><op text="/"/><number text="0"/></expr></assignstmt>
          <assignstmt><dsgn><node text="Defaulted"/></dsgn><expr><number text="2"/></expr></assignstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.variables["given"], "1", "the handler ran")
        XCTAssertNil(engine.state.script.variables["seen"], "no value assigned")
        XCTAssertEqual(engine.state.script.variables["defaulted"], "1", "uncaught: the run ended there, what it did kept")
        XCTAssertNil(engine.state.script.variables["where"])
    }

    /// Comparisons are numeric when a number meets a number, or text that reads as one; text
    /// against text compares as text, as Delphi's variants do.
    func testComparisonsMeetNumbersAsNumbers() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <assignstmt><dsgn><node text="Seen"/></dsgn><expr><string text="'1.0'"/><op text="="/><number text="1"/></expr></assignstmt>
          <assignstmt><dsgn><node text="Given"/></dsgn><expr><string text="'10'"/><op text="&lt;"/><string text="'9'"/></expr></assignstmt>
          <assignstmt><dsgn><node text="Defaulted"/></dsgn><expr><string text="'a'"/><op text="="/><number text="0"/></expr></assignstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.variables["seen"], "1", "'1.0' = 1")
        XCTAssertEqual(engine.state.script.variables["given"], "1", "'10' < '9' as text")
        XCTAssertEqual(engine.state.script.variables["defaulted"], "0", "text that is no number is not 0")
    }

    // MARK: - Host calls

    /// A runaway loop of host calls, the costliest steps skins take, stops at the step limit within
    /// a frame at 30 fps: a frame waits on its scripts, which run on the AIMP queue. Timed in an
    /// optimized build only (`swift test -Xswiftc -O`); a debug build runs it about ten times slower.
    func testRunawayHostCallsStopWithinAFrame() throws {
        let engine = try Self.engine()
        let program = try AIMPSkinScript.compile(Self.node("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <whilestmt><expr><number text="1"/></expr><compoundstmt>
            <assignstmt><dsgn><node text="Where"/></dsgn><expr><dsgn><node text="BindingsGetDataAsText3"/>
              <expr><string text="'prvPlayingFileInfo'"/></expr><expr><string text="'FileInfo'"/></expr>
              <expr><string text="''"/></expr><expr><string text="'%R'"/></expr></dsgn></expr></assignstmt>
          </compoundstmt></whilestmt>
        </compoundstmt></procedure></program>
        """))
        let began = CFAbsoluteTimeGetCurrent()
        XCTAssertThrowsError(try engine.run(program)) { XCTAssertTrue($0 is AIMPSkinScript.Budget.Spent) }
        let spent = (CFAbsoluteTimeGetCurrent() - began) * 1_000
        XCTAssertEqual(engine.budget.steps, AIMPSkinScript.Budget.stepLimit)
        print("AIMP script budget: \(AIMPSkinScript.Budget.stepLimit) host-call steps spent in \(Int(spent)) ms")
        var optimized = true
        assert({ optimized = false; return true }())
        if optimized { XCTAssertLessThan(spent, 1_000 / 30) }
    }

    /// `BindingsGetDataAsText3(source, pin, expression, format)` formats the playing file's tags.
    func testBindingsGetDataAsText3FormatsFileInfo() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <assignstmt><dsgn><node text="Where"/></dsgn><expr><dsgn><node text="BindingsGetDataAsText3"/>
            <expr><string text="'prvPlayingFileInfo'"/></expr><expr><string text="'FileInfo'"/></expr>
            <expr><string text="''"/></expr><expr><string text="'%R'"/></expr></dsgn></expr></assignstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.variables["where"], AIMPSkinPlayerSnapshot.probe.artist)
    }

    /// Calls for player features NullPlayer lacks finish with a neutral answer: the colour dialog
    /// reads as cancelled, switching skins and seeding `Random` do nothing.
    func testHostCallsNullPlayerLacksAreNeutral() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <callstmt><dsgn><node text="Randomize"/></dsgn></callstmt>
          <callstmt><dsgn><node text="ApplySkin"/><expr><string text="'Other'"/></expr></dsgn></callstmt>
          <assignstmt><dsgn><node text="Seen"/></dsgn>
            <expr><dsgn><node text="ExecuteColorPicker"/><expr><number text="0"/></expr></dsgn></expr></assignstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.variables["seen"], "0")
        XCTAssertTrue(engine.actions.isEmpty)
    }

    /// A link handle is the link, not the pin it was added under: `L` moved to pin `B` and a second
    /// `LinkAdd('A')` are two links, and setting `L` afterwards does not reach the second one.
    func testALinkHandleKeepsItsLinkWhenItsPinIsReused() throws {
        func get(_ object: String, _ attribute: String) -> String { Self.call(object, "Get", attribute) }
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          \(Self.assign("B", "<dsgn><node text=\"TASEBindings\"/><node text=\"Create\"/></dsgn>"))
          \(Self.assign("L", Self.call("B", "LinkAdd", "A")))
          <callstmt>\(Self.call("L", "Set", "TargetPin", "B"))</callstmt>
          \(Self.assign("M", Self.call("B", "LinkAdd", "A")))
          <callstmt>\(Self.call("M", "Set", "Source", "Second"))</callstmt>
          <callstmt>\(Self.call("L", "Set", "Source", "First"))</callstmt>
          \(Self.assign("N", Self.call("B", "LinkFind", "B")))
          \(Self.assign("Where", get("L", "TargetPin") + "<op text=\"+\"/>" + get("L", "Source") + "<op text=\"+\"/>"
              + get("M", "TargetPin") + "<op text=\"+\"/>" + get("M", "Source") + "<op text=\"+\"/>" + get("N", "Source")))
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.variables["where"], "BFirstASecondFirst")
    }

    /// `nil` compares with a link handle by identity: `LinkFind` of a pin with a link is not `nil`,
    /// of one without is.
    func testLinkFindComparesWithNilByIdentity() throws {
        let isNil = { (pin: String) in Self.call("B", "LinkFind", pin) + "<op text=\"=\"/><dsgn><node text=\"nil\"/></dsgn>" }
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          \(Self.assign("B", "<dsgn><node text=\"TASEBindings\"/><node text=\"Create\"/></dsgn>"))
          \(Self.assign("L", Self.call("B", "LinkAdd", "A")))
          \(Self.assign("Given", isNil("A")))
          \(Self.assign("Seen", isNil("Missing")))
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.state.script.variables["given"], "0", "a link that exists is not nil")
        XCTAssertEqual(engine.state.script.variables["seen"], "1", "a missing link is nil")
    }

    /// A length a server sends out of `Int`'s range is held, not trapped on.
    @MainActor func testATrackLengthOutOfRangeIsBounded() {
        XCTAssertEqual(AIMPSkinAudioEngineHost.seconds(9.3e18), 31_536_000_000)
        XCTAssertEqual(AIMPSkinAudioEngineHost.seconds(.infinity), 0)
        XCTAssertEqual(AIMPSkinAudioEngineHost.seconds(-3), 0)
        XCTAssertEqual(AIMPSkinAudioEngineHost.seconds(61.9), 61)
    }

    /// The effect resets set speed and tempo to 1 and pitch to 0: tempo moves NullPlayer's speed,
    /// pitch its pitch shift, and each value is the knob's middle (normal speed, no shift).
    func testTempoMovesTheSpeedAndPitchThePitchShift() throws {
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <callstmt><dsgn><node text="FindObject"/><expr><string text="'prvTempo'"/></expr><node text="Set"/>
            <expr><string text="'Position'"/></expr><expr><number text="1"/></expr></dsgn></callstmt>
          <callstmt><dsgn><node text="FindObject"/><expr><string text="'prvPitch'"/></expr><node text="Set"/>
            <expr><string text="'Position'"/></expr><expr><number text="0"/></expr></dsgn></callstmt>
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.actions, [.set(.speed, 0.5), .set(.pitch, 0.5)])
    }

    /// AIMP bands that share a NullPlayer band are asked for once, at their mean; a band written
    /// twice counts as its latest.
    func testEqualizerWritesAreAskedForOncePerBand() throws {
        let band = { (aimp: Int) in AIMPSkinPlayerSnapshot.probe.eqBand(aimp: aimp, aimp5: false) }
        let one = try XCTUnwrap((1..<18).first { band($0) == band($0 + 1) }, "no two AIMP bands share a NullPlayer band")
        let first = try XCTUnwrap(band(one)), shared = one + 1
        func write(_ aimp: Int, _ dB: Int) -> String {
            """
            <callstmt><dsgn><node text="FindObject"/><expr><string text="'prvEqualizer'"/></expr><node text="Set"/>
              <expr><string text="'BandValue\(aimp)'"/></expr><expr><number text="\(dB)"/></expr></dsgn></callstmt>
            """
        }
        let engine = try Self.run("""
        <program><procedure><name text="Execute"/><compoundstmt>
          \(write(one, 2)) \(write(one, 4)) \(write(shared, 8))
        </compoundstmt></procedure></program>
        """)
        XCTAssertEqual(engine.actions, [.set(.equalizerBand(first), 0.75)], "6 dB")
    }

    /// `Insert` is held to the text limit `+` is, so a loop doubling a string stops the run; a
    /// `FormatFloat` pattern of thousands of zeros gives at most `formatWidthLimit` decimals.
    func testInsertAndFormatFloatAreBounded() throws {
        let half = String(repeating: "a", count: AIMPSkinScript.Run.textLimit / 2 + 1)
        XCTAssertThrowsError(try AIMPSkinScript.Builtin.insert.call([.string(half), .string(half), .number(1)]))
        let small = try AIMPSkinScript.Builtin.insert.call([.string("b"), .string("ac"), .number(2)])
        XCTAssertEqual(small.outputs[1]?.string, "abc")
        let pattern = "0." + String(repeating: "0", count: 100_000)
        let formatted = try AIMPSkinScript.Builtin.formatFloat.call([.string(pattern), .number(1)])
        XCTAssertLessThanOrEqual(formatted.value.string.count, 2 + AIMPSkinScript.formatWidthLimit)
        XCTAssertTrue(formatted.value.string.hasPrefix("1.000"))
    }

    /// Text work is charged by the byte: a loop copying a long text over and over, each pass under
    /// the text limit, spends the budget long before its steps do, so one tick cannot move
    /// gigabytes a step at a time.
    func testCopyingLongTextSpendsTheBudget() throws {
        let skin = try Self.skin(scripts: ["Churn": """
        <program><procedure><name text="Execute"/><compoundstmt>
          <assignstmt><dsgn><node text="Where"/></dsgn><expr><string text="'ab'"/></expr></assignstmt>
          <whilestmt><expr><number text="1"/></expr><compoundstmt>
            <assignstmt><dsgn><node text="Where"/></dsgn>
              <expr><dsgn><node text="Copy"/>
                <expr><dsgn><node text="Where"/></dsgn><op text="+"/><dsgn><node text="Where"/></dsgn></expr>
                <expr><number text="1"/></expr><expr><number text="30000"/></expr></dsgn></expr></assignstmt>
          </compoundstmt></whilestmt>
        </compoundstmt></procedure></program>
        """])
        let budget = AIMPSkinScript.Budget()
        let engine = AIMPSkinScript.Engine(skin: skin, host: AIMPSkinHostState(player: .probe), state: AIMPSkinState(), budget: budget)
        XCTAssertTrue(engine.handle("Churn", sender: "Churn"), "stopped on a limit")
        XCTAssertTrue(budget.isSpent)
        XCTAssertLessThan(budget.steps, 500, "spent by bytes, not steps")
    }

    /// A handler the text limit stops is undone as one the step budget stops is, though the tick's
    /// step budget is not spent: what it set before the limit does not stay.
    func testAHandlerStoppedByTheTextLimitIsUndone() throws {
        let skin = try Self.skin(scripts: ["Grow": """
        <program><procedure><name text="Execute"/><compoundstmt>
          <assignstmt><dsgn><node text="Given"/></dsgn><expr><number text="1"/></expr></assignstmt>
          <assignstmt><dsgn><node text="Where"/></dsgn><expr><string text="'ab'"/></expr></assignstmt>
          <whilestmt><expr><number text="1"/></expr><compoundstmt>
            <assignstmt><dsgn><node text="Where"/></dsgn>
              <expr><dsgn><node text="Where"/></dsgn><op text="+"/><dsgn><node text="Where"/></dsgn></expr></assignstmt>
          </compoundstmt></whilestmt>
        </compoundstmt></procedure></program>
        """])
        let budget = AIMPSkinScript.Budget()
        let engine = AIMPSkinScript.Engine(skin: skin, host: AIMPSkinHostState(player: .probe), state: AIMPSkinState(), budget: budget)
        XCTAssertTrue(engine.handle("Grow", sender: "Grow"), "stopped on a limit")
        XCTAssertFalse(budget.isSpent, "the text limit, not the step budget")
        XCTAssertEqual(engine.state.script.variables["given"] ?? "0", "0")
    }

    /// A form docks and undocks into the site that holds it, and a name no site holds is not kept;
    /// an item moves only into an item of the skin, never under what it holds; a control moves into
    /// an item or a control. Each refused move is checked on its own.
    func testDockingAndMovingItems() throws {
        func site(_ form: String) -> String {
            "<item class=\"LayoutDockSite\" name=\"\(form)Site\"><properties><property name=\"ControlName\" value=\"\(form)\"/></properties></item>"
        }
        let skin = try Self.skin(form: """
        <layout><items><item name="AioHost"/><item name="Table"><items><item name="Inner"/></items></item>
          \(site("LibraryForm"))\(site("PlaylistForm"))</items>
          <controls><control name="Knob" class="Button"/><control name="Holder" class="Button"/></controls></layout>
        """, entries: ["LibraryForm", "PlaylistForm"].map { ("\($0).xml", "<form name=\"\($0)\"/>") })
        let engine = AIMPSkinScript.Engine(skin: skin, host: AIMPSkinHostState(player: .probe), state: AIMPSkinState())
        func find(_ name: String) -> String { "<dsgn><node text=\"FindObject\"/><expr><string text=\"'\(name)'\"/></expr></dsgn>" }
        func run(_ statements: String) throws {
            try engine.run(AIMPSkinScript.compile(Self.node(
                "<program><procedure><name text=\"Execute\"/><compoundstmt>\(statements)</compoundstmt></procedure></program>")))
        }
        func move(_ name: String, into parent: String) throws {
            try run("""
            <assignstmt><dsgn><node text="FindObject"/><expr><string text="'\(name)'"/></expr><node text="Parent"/></dsgn>
              <expr>\(find(parent))</expr></assignstmt>
            """)
        }

        try move("Table", into: "Missing")
        XCTAssertEqual(engine.state.script.parents, [:], "a holder the skin lacks")
        try move("Table", into: "Inner")
        XCTAssertEqual(engine.state.script.parents, [:], "under what it holds")
        try move("Table", into: "Knob")
        XCTAssertEqual(engine.state.script.parents, [:], "an item into a control")

        try run("""
        <callstmt><dsgn><node text="FindObject"/><expr><string text="'LibraryForm'"/></expr><node text="Undock"/></dsgn></callstmt>
        <callstmt><dsgn><node text="FindObject"/><expr><string text="'PlaylistForm'"/></expr><node text="Dock"/></dsgn></callstmt>
        <callstmt><dsgn><node text="FindObject"/><expr><string text="'NoSuchForm'"/></expr><node text="Dock"/></dsgn></callstmt>
        """)
        XCTAssertEqual(engine.state.script.objects.values(\.docked), ["LibraryForm": false, "PlaylistForm": true])

        try move("Table", into: "AioHost")
        XCTAssertEqual(engine.state.script.parents, ["Table": "AioHost"])
        try move("Knob", into: "Holder")
        XCTAssertEqual(engine.state.script.parents, ["Table": "AioHost", "Knob": "Holder"], "a control into a control")
        try run("""
        <assignstmt><dsgn><node text="Where"/></dsgn>
          <expr><dsgn><node text="FindObject"/><expr><string text="'Table'"/></expr><node text="Parent"/></dsgn></expr></assignstmt>
        """)
        XCTAssertEqual(engine.state.script.variables["where"], "AioHost")
    }

    /// Once either limit of a shared budget is spent, a later run on it stops at its first step: a
    /// job after one that spent the text budget commits nothing.
    func testASpentTextBudgetStopsTheNextRunsSteps() throws {
        let budget = AIMPSkinScript.Budget()
        XCTAssertThrowsError(try budget.charge(AIMPSkinScript.Budget.byteLimit))
        XCTAssertThrowsError(try budget.step(), "the text budget is spent")
        let skin = try Self.skin(scripts: ["Count": """
        <program><procedure><name text="Execute"/><compoundstmt>
          <assignstmt><dsgn><node text="Given"/></dsgn><expr><number text="1"/></expr></assignstmt>
        </compoundstmt></procedure></program>
        """])
        let engine = AIMPSkinScript.Engine(skin: skin, host: AIMPSkinHostState(player: .probe), state: AIMPSkinState(), budget: budget)
        XCTAssertTrue(engine.handle("Count", sender: "Count"), "stopped on the limit")
        XCTAssertEqual(engine.state.script.variables["given"] ?? "0", "0")
    }

    /// `FindResource(id).Set('ID', …)` keeps as many aliases as `ConfigSet` keeps keys: a loop of
    /// fresh names stops growing the state; an alias already kept can still be repointed.
    func testResourceAliasesAreHeldToTheStoreLimit() throws {
        let engine = try Self.engine()
        func repoint(_ id: String, to target: String) throws {
            try engine.run(AIMPSkinScript.compile(Self.node("""
            <program><procedure><name text="Execute"/><compoundstmt>
              <callstmt><dsgn><node text="FindResource"/><expr><string text="'\(id)'"/></expr><node text="Set"/>
                <expr><string text="'ID'"/></expr><expr><string text="'\(target)'"/></expr></dsgn></callstmt>
            </compoundstmt></procedure></program>
            """)))
        }
        let limit = AIMPSkinScript.Run.storedKeyLimit
        for index in 0..<(limit + 5) { try repoint("Skin.Alias\(index)", to: "Skin.Face") }
        XCTAssertEqual(engine.state.script.resourceLinks.count, limit)
        try repoint("Skin.Alias0", to: "Skin.Face_7")
        XCTAssertEqual(engine.state.script.resourceLinks["Skin.Alias0"], "Skin.Face_7")
        try repoint("Skin.Alias1", to: String(repeating: "x", count: AIMPSkinScript.Run.longestPropertyPath + 1))
        XCTAssertEqual(engine.state.script.resourceLinks["Skin.Alias1"], "Skin.Face", "a target too long is not kept")
    }

    /// A cleared binding set's links stay gone: a new link takes a fresh id, so a handle the script
    /// kept to an old one finds nothing.
    func testAClearedBindingSetKeepsOldHandlesInvalid() {
        var set = AIMPSkinScript.BindingSet()
        let old = set.add(AIMPSkinLink(source: "A", pin: "Position", target: "Value", names: AIMPSkinIndex.Names()))
        set.removeAll()
        let new = set.add(AIMPSkinLink(source: "B", pin: "Position", target: "Value", names: AIMPSkinIndex.Names()))
        XCTAssertNotEqual(old, new)
        XCTAssertNil(set[old])
        XCTAssertEqual(set[new]?.source, "B")
    }

    /// A flat chain of operands deeper than evaluation goes does not compile, so its tree is never
    /// built (freeing one a million levels deep overflowed the stack); one within the limit does.
    func testAnExpressionDeeperThanTheLimitDoesNotCompile() throws {
        func program(operands: Int) throws -> AIMPNode {
            let chain = Array(repeating: #"<number text="1"/>"#, count: operands).joined(separator: #"<op text="+"/>"#)
            return try Self.node("""
            <program><procedure><name text="Execute"/><compoundstmt>
              <assignstmt><dsgn><node text="Given"/></dsgn><expr>\(chain)</expr></assignstmt>
            </compoundstmt></procedure></program>
            """)
        }
        let limit = AIMPSkinScript.Run.expressionDepthLimit
        XCTAssertThrowsError(try AIMPSkinScript.compile(program(operands: 100_000)))
        XCTAssertThrowsError(try AIMPSkinScript.compile(program(operands: limit + 1)))
        XCTAssertNoThrow(try AIMPSkinScript.compile(program(operands: 100)))
        let unary = String(repeating: #"<op text="-"/>"#, count: 10_000) + #"<number text="1"/>"#
        XCTAssertThrowsError(try AIMPSkinScript.compile(Self.node("""
        <program><procedure><name text="Execute"/><compoundstmt>
          <assignstmt><dsgn><node text="Given"/></dsgn><expr>\(unary)</expr></assignstmt>
        </compoundstmt></procedure></program>
        """)))
    }

    /// A property path no skin writes, thousands of names long, is not kept (laying it over the
    /// control nested a property per name); a skin's own dotted path is.
    func testAPropertyPathTooLongIsNotKept() throws {
        let skin = try Self.skin(form: #"<layout><controls><control name="Knob" class="Button"/></controls></layout>"#)
        let engine = AIMPSkinScript.Engine(skin: skin, host: AIMPSkinHostState(player: .probe), state: AIMPSkinState())
        func set(_ path: String) throws {
            try engine.run(AIMPSkinScript.compile(Self.node("""
            <program><procedure><name text="Execute"/><compoundstmt>
              <callstmt><dsgn><node text="FindObject"/><expr><string text="'Knob'"/></expr><node text="Set"/>
                <expr><string text="'\(path)'"/></expr><expr><number text="1"/></expr></dsgn></callstmt>
            </compoundstmt></procedure></program>
            """)))
        }
        try set(Array(repeating: "a", count: 20_000).joined(separator: "."))
        try set(String(repeating: "b", count: 1_000))
        XCTAssertEqual(engine.state.script["Knob"].properties, [:])
        try set("Resources.ItemBackgroundColors.Playing")
        XCTAssertEqual(Array(engine.state.script["Knob"].properties.keys), ["Resources.ItemBackgroundColors.Playing"])
    }

    // MARK: - Helpers

    static func node(_ xml: String) throws -> AIMPNode {
        try AIMPNode.parse(Data(xml.utf8), name: "test.xml")
    }

    /// FastScript's tree (`.fsxml`) of `object.method('arg'…)`.
    static func call(_ object: String, _ method: String, _ args: String...) -> String {
        "<dsgn><node text=\"\(object)\"/><node text=\"\(method)\"/>"
            + args.map { "<expr><string text=\"'\($0)'\"/></expr>" }.joined() + "</dsgn>"
    }

    /// FastScript's tree of `name := value`, `value` a tree itself.
    static func assign(_ name: String, _ value: String) -> String {
        "<assignstmt><dsgn><node text=\"\(name)\"/></dsgn><expr>\(value)</expr></assignstmt>"
    }

    /// `program` compiled and run once from a fresh state; its results are the skin's variables.
    private static func run(_ program: String) throws -> AIMPSkinScript.Engine {
        let engine = try engine()
        try engine.run(AIMPSkinScript.compile(node(program)))
        return engine
    }

    private static func engine() throws -> AIMPSkinScript.Engine {
        AIMPSkinScript.Engine(skin: try skin(), host: AIMPSkinHostState(player: .probe), state: AIMPSkinState())
    }

    /// A project file (`ACSJ`) holding one main form (empty unless given), any `more` entries, compiled
    /// `scripts` by name (`<name>.fsxml`), and a `Schema.xml` declaring the variables the tests read
    /// their results from: what a script needs of a skin.
    static func skin(form: String = #"<form name="AIMPMainForm"/>"#, entries more: [(String, String)] = [],
                     scripts: [String: String] = [:], files: [(String, Data)] = []) throws -> AIMPSkin {
        let schema = """
        <schema><variables><variable name="Defaulted" value="0"/><variable name="Given" value="0"/><variable name="Seen" value="0"/>
          <variable name="Where" value="" valueType="String"/></variables></schema>
        """
        let entries = ([("AIMPMainForm.xml", form), ("Schema.xml", schema)] + more).map { ($0, Data($1.utf8)) }
            + (try scripts.sorted { $0.key < $1.key }.map { ("\($0.key).fsxml", fsxml(try node($0.value))) }) + files
        return try AIMPSkinLoader.load(data: AIMPTestProject.data(entries))
    }

    /// `tree` as AIMP stores a compiled script (`FSXMLBIN`, `AIMPSkinScript.parse`).
    static func fsxml(_ tree: AIMPNode) -> Data {
        func wide(_ text: String) -> Data {
            Data([UInt8(text.utf16.count & 0xFF), UInt8(text.utf16.count >> 8)]) + (text.data(using: .utf16LittleEndian) ?? Data())
        }
        func encode(_ node: AIMPNode) -> Data {
            // Escaped, so the decoder's entity pass gives each value back as it was (`&` and `"` included).
            let attributes = node.attributes.sorted { $0.key < $1.key }.map { key, value in
                "\(key)=\"\(value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;"))\""
            }.joined(separator: " ")
            return node.children.reduce(wide(node.tag) + wide(attributes) + withUnsafeBytes(of: UInt32(node.children.count).littleEndian) { Data($0) }) {
                $0 + encode($1)
            }
        }
        return Data("FSXMLBIN".utf8) + encode(tree)
    }
}
