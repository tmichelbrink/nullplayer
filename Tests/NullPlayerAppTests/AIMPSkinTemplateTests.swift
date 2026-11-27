import XCTest
@testable import NullPlayer

/// `AIMPSkinTemplate`: a text control's template (`%time`, `%IF`, the track's fields, the string
/// functions) as AIMP formats it.
final class AIMPSkinTemplateTests: XCTestCase {
    func testTimeTemplatesLeaveOutZeroHoursWhenAsked() {
        let host = AIMPSkinHostState()
        XCTAssertEqual(AIMPSkinTemplate.format("%time(HMS;:;Z)", host: host, value: 159), "2:39", "M5's wave-bar times")
        XCTAssertEqual(AIMPSkinTemplate.format("%time(HMS;:;Z)", host: host, value: 3_725), "1:02:05")
        XCTAssertEqual(AIMPSkinTemplate.format("%time(HMS;:;)", host: host, value: 159), "0:02:39")
        XCTAssertEqual(AIMPSkinTemplate.format("%time(MS;.;)", host: host, value: 159), "2.39")
    }

    func testIfTakesEmptyAndZeroAsFalse() {
        let host = AIMPSkinHostState()
        // Terran's timer: its counter reads 0 until clicked, and the track's time shows till then.
        XCTAssertEqual(AIMPSkinTemplate.format("%IF(0,sleep,track)", host: host), "track")
        XCTAssertEqual(AIMPSkinTemplate.format("%IF(1,sleep,track)", host: host), "sleep")
        XCTAssertEqual(AIMPSkinTemplate.format("%IF(,a,b)", host: host), "b")
        XCTAssertEqual(AIMPSkinTemplate.format("%IF(Artist,a,b)", host: host), "a")
        XCTAssertEqual(AIMPSkinTemplate.format("%IF(0.00 MB,a,b)", host: host), "a", "text, not a number")
    }

    func testFileAndStatisticsFieldsReadThePlayingTrack() {
        var host = AIMPSkinHostState()
        host.player.title = "Song"
        host.player.fileType = "FLAC"
        host.player.sampleRate = 44_100
        host.player.fileDirectory = "/Music/Album"
        host.player.playCount = 3
        host.player.discNumber = 2
        XCTAssertEqual(AIMPSkinTemplate.format("%IF(%FileFormat,%FileFormat%Char(44) ,)%SampleRate", host: host), "FLAC, 44 kHz")
        XCTAssertEqual(AIMPSkinTemplate.format("%FileName.%FileFormat", host: host), "Song.FLAC", "a stream's name is its title")
        host.player.fileName = "01 song"
        XCTAssertEqual(AIMPSkinTemplate.format("%FileName.%FileFormat", host: host), "01 song.FLAC")
        XCTAssertEqual(AIMPSkinTemplate.format("%playcount/%PlayCount %FileDir %FileParentDir %DiskNumber", host: host), "3/3 /Music/Album Album 2")
        XCTAssertEqual(AIMPSkinTemplate.format("%a|%A|%TrackGain", host: host), "||", "short fields keep their case; missing tags read empty")
        XCTAssertEqual(AIMPSkinTemplate.format("%LastPlayDate", host: host), "-", "no statistics, as AIMP 5.40 shows them")
        host.player.fileSize = 352_880
        XCTAssertEqual(AIMPSkinTemplate.format("%FileSize", host: host), "344.61 KB")
        host.player.lastPlayed = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(AIMPSkinTemplate.format("%LastPlayDate", host: host).isEmpty)
    }

    /// As AIMP 5.40 shows them (a track tagged 7/12, first of one and of 101 in the list, at
    /// 20:18:20 on 2026-11-27, with no play statistics).
    func testShortFieldsReadAsAIMPShowsThem() {
        var host = AIMPSkinHostState()
        host.player.trackNumber = 7
        host.player.playlistIndex = 0
        host.player.timeOfDay = 20 * 3_600 + 18 * 60 + 20
        host.player.today = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 11, day: 27, hour: 12).date
        XCTAssertEqual(AIMPSkinTemplate.format("a[%TN]b[%TC]c[%DC]d[%RT]", host: host), "a[7]b[20:18:20]c[2026.11.27]d[-]")
        XCTAssertEqual(AIMPSkinTemplate.format("e[%TrackNumber]h[%Rating]i[%IN]", host: host), "e[7]h[-]i[01]")
        host.player.trackNumber = 0
        host.player.playlistIndex = 100
        host.player.today = nil
        XCTAssertEqual(AIMPSkinTemplate.format("a[%TN]i[%IN]c[%DC]", host: host), "a[]i[101]c[]", "untagged reads empty")
    }

    func testTextTemplatesSplitAndMeasureAsAIMPCounts() {
        let host = AIMPSkinHostState()
        // Soot's off and on labels, split from one language string.
        XCTAssertEqual(AIMPSkinTemplate.format("%StrLeft(Off|On,%Dec(%StrPos(|,Off|On),1))", host: host), "Off")
        XCTAssertEqual(AIMPSkinTemplate.format("%StrRight(Off|On,%Dec(%Length(Off|On),%StrPos(|,Off|On)))", host: host), "On")
        XCTAssertEqual(AIMPSkinTemplate.format("%StrPos(x,abc)", host: host), "0")
        XCTAssertEqual(AIMPSkinTemplate.format("%Copy(abcdef,2,3)", host: host), "bcd")
        XCTAssertEqual(AIMPSkinTemplate.format("%Inc(4)", host: host), "5")
    }
}
