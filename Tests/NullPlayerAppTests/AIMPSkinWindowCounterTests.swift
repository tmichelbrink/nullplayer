import XCTest
@testable import NullPlayer

/// A companion window whose `Schema.xml` entry binds its `Visibility` to a counter's `Position`
/// (TASCAM CD-RW750's EQUALIZER and PLST keys): as in AIMP 5.40, it opens as `InitialVisible` says,
/// and follows the counter only as the counter turns.
final class AIMPSkinWindowCounterTests: XCTestCase {
    private func skin() throws -> AIMPSkin {
        let key = { (name: String, counter: String) in
            """
            <control class="Button" name="\(name)"><properties><property name="Bindings">
              <link Source="\(counter)" SourcePin="Position" TargetPin="Action" Expression="Value+1"/>
            </property><property name="PlaceInfo" margins="0,0,0,0" Size="10,10"/></properties></control>
            """
        }
        let main = """
        <layout><items><item name="Body"><properties><property name="Size" value="120,60"/>
          <property name="Color" value="-1"/></properties><controls>\(key("EQBtn", "EQ_Counter"))\(key("PlsBtn", "PL_Counter"))</controls>
        </item></items></layout>
        """
        let window = """
        <layout><items><item name="Unit"><properties><property name="Size" value="120,60"/>
          <property name="Color" value="-1"/></properties></item></items></layout>
        """
        let schema = """
        <schema><forms>
          <form name="AIMPMainForm"/>
          <form name="PlaylistForm" master="AIMPMainForm"><properties><property name="Bindings">
            <link Source="PL_Counter" SourcePin="Position" TargetPin="Visibility"/></property></properties></form>
          <form name="EQForm" master="AIMPMainForm"><properties><property name="Bindings">
            <link Source="EQ_Counter" SourcePin="Position" TargetPin="Visibility"/></property>
            <property name="InitialVisible" value="False"/></properties></form>
        </forms><providers>
          <provider name="EQ_Counter" class="LogicalOperatorCounter"><properties><property name="Module" value="2"/></properties></provider>
          <provider name="PL_Counter" class="LogicalOperatorCounter"><properties><property name="Module" value="2"/></properties></provider>
        </providers></schema>
        """
        return try AIMPSkinLoader.load(data: AIMPSkinFormWindowMaterializerTests.project(
            [("AIMPMainForm.xml", main), ("Schema.xml", schema), ("PlaylistForm.xml", window), ("EQForm.xml", window)]))
    }

    private func pressed(_ skin: AIMPSkin, _ counter: String, _ state: AIMPSkinState) -> AIMPSkinState {
        AIMPSkinScript.perform([.stepCounter(counter, by: AIMPSkinStep("Value+1"), notches: 1)],
                               skin: skin, host: AIMPSkinHostState(), state: state).state
    }

    private func shown(_ skin: AIMPSkin, _ state: AIMPSkinState) -> [Bool] {
        let flow = AIMPSkinDataflow(skin: skin, host: AIMPSkinHostState(), state: state)
        return [flow.isVisible("PlaylistForm"), flow.isVisible("EQForm")]
    }

    func testTheCountersShowAndHideTheirWindowsAsTheyTurn() throws {
        let skin = try skin()
        XCTAssertEqual(skin.index.windowCounters.keys.sorted(), ["EQ_Counter", "PL_Counter"])
        var state = AIMPSkinState()
        XCTAssertEqual(shown(skin, state), [true, false], "as InitialVisible says, not the counters at 0")
        state = pressed(skin, "EQ_Counter", state)
        XCTAssertEqual(shown(skin, state), [true, true], "EQUALIZER opens the equalizer")
        state = pressed(skin, "EQ_Counter", state)
        XCTAssertEqual(shown(skin, state), [true, false], "and closes it")
        // AIMP 5.40: the first press on PLST turns its counter to 1 with the playlist already shown;
        // the second hides it, the third shows it.
        state = pressed(skin, "PL_Counter", state)
        XCTAssertEqual(shown(skin, state), [true, false])
        state = pressed(skin, "PL_Counter", state)
        XCTAssertEqual(shown(skin, state), [false, false])
        state = pressed(skin, "PL_Counter", state)
        XCTAssertEqual(shown(skin, state), [true, false])
    }
}
