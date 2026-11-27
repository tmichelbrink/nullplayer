import XCTest
@testable import NullPlayer

/// `LogicalOperatorMultiplexer`: its `Result` is the value its `Switch` picks, `Value1` at 1 (FLAT
/// DARK's time read-out shows the track's length, or what is left of it, by a counter).
final class AIMPSkinMultiplexerTests: XCTestCase {
    func testTheSwitchPicksTheValue() throws {
        let schema = """
        <schema><forms><form name="AIMPMainForm"/></forms><providers>
          <provider name="Mode" class="LogicalOperatorCounter"><properties><property name="Module" value="3"/></properties></provider>
          <provider name="Pick" class="LogicalOperatorMultiplexer"><properties><property name="Bindings">
            <link Source="Mode" SourcePin="Position" TargetPin="Switch" Expression="Value + 1"/>
            <link Source="prvPlayerState" SourcePin="TrackDuration" TargetPin="Value1"/>
            <link Source="prvPlayerState" SourcePin="TrackPositionRemaining" TargetPin="Value2"/>
          </property></properties></provider>
        </providers></schema>
        """
        let main = """
        <layout><items><item name="Body"><properties><property name="Size" value="120,60"/>
          <property name="Color" value="-1"/></properties></item></items></layout>
        """
        let skin = try AIMPSkinLoader.load(data: AIMPSkinFormWindowMaterializerTests.project([("AIMPMainForm.xml", main), ("Schema.xml", schema)]))
        XCTAssertEqual(skin.index.providers["Pick"]?.kind, .multiplexer)
        var host = AIMPSkinHostState()
        host.player.durationSeconds = 200
        host.player.elapsedSeconds = 50
        var state = AIMPSkinState()
        let result = { AIMPSkinDataflow(skin: skin, host: host, state: state).value("Pick", "Result") }
        XCTAssertEqual(result(), 200, "Switch 1: Value1, the length")
        state.script["Mode"].counter = 1
        XCTAssertEqual(result(), 150, "Switch 2: Value2, what is left")
        state.script["Mode"].counter = 2
        XCTAssertEqual(result(), 0, "Switch 3: no Value3")
    }
}
