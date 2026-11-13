import XCTest
@testable import VibeCore

final class XtreamTests: XCTestCase {
    private let account = XtreamAccount(base: "http://host.tld:8080", username: "user", password: "p@ss/word")
    private let playlist = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func testNormalizeServer() {
        XCTAssertEqual(Xtream.normalizeServer("host.tld:8080"), "http://host.tld:8080")
        XCTAssertEqual(Xtream.normalizeServer(" https://host.tld/ "), "https://host.tld")
        XCTAssertEqual(Xtream.normalizeServer("http://host.tld:80/player_api.php?username=a&password=b"), "http://host.tld:80")
        XCTAssertNil(Xtream.normalizeServer(""))
        XCTAssertNil(Xtream.normalizeServer("http://"))
    }

    func testAccountFromGetPhpAddress() {
        let a = Xtream.account(fromURL: "http://host.tld:8080/get.php?username=me&password=a%2Bb&type=m3u_plus&output=ts")
        XCTAssertEqual(a, XtreamAccount(base: "http://host.tld:8080", username: "me", password: "a+b"))
        XCTAssertNil(Xtream.account(fromURL: "http://host.tld/list.m3u"))
        XCTAssertNil(Xtream.account(fromURL: "http://host.tld/get.php?username=me"))
    }

    func testAddressesEncodeSpecialCharacters() {
        XCTAssertEqual(Xtream.liveURL(account, id: "12"), "http://host.tld:8080/live/user/p%40ss%2Fword/12.m3u8")
        XCTAssertEqual(Xtream.liveURL(account, id: "12", hls: false), "http://host.tld:8080/live/user/p%40ss%2Fword/12.ts")
        XCTAssertEqual(Xtream.movieURL(account, id: "7", ext: ".MKV"), "http://host.tld:8080/movie/user/p%40ss%2Fword/7.mkv")
        XCTAssertEqual(Xtream.episodeURL(account, id: "7", ext: "../x"), "http://host.tld:8080/series/user/p%40ss%2Fword/7.mp4")
        let api = Xtream.apiURL(account, action: "get_live_streams", params: [("category_id", "5")])
        XCTAssertEqual(api?.absoluteString,
                       "http://host.tld:8080/player_api.php?username=user&password=p%40ss%2Fword&action=get_live_streams&category_id=5")
    }

    func testAuth() {
        let ok = Xtream.parseAuth(Data(#"{"user_info":{"auth":1,"status":"Active","exp_date":"1900000000","max_connections":"2","active_cons":0}}"#.utf8))
        XCTAssertEqual(ok.ok, true)
        XCTAssertEqual(ok.maxConnections, 2)
        XCTAssertEqual(ok.activeConnections, 0)
        XCTAssertEqual(ok.expires, Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertEqual(Xtream.parseAuth(Data(#"{"user_info":{"auth":0}}"#.utf8)).ok, false)
        XCTAssertEqual(Xtream.parseAuth(Data(#"{"user_info":{"auth":1,"status":"Expired"}}"#.utf8)).ok, false)
        XCTAssertNil(Xtream.parseAuth(Data("<html>".utf8)).ok)
    }

    func testCategoriesAndItemsTolerateMixedTypes() {
        let cats = Xtream.parseCategories(Data(#"[{"category_id":"3","category_name":"News"},{"category_id":4,"category_name":"Sport"},{"category_name":"broken"}]"#.utf8), kind: .live)
        XCTAssertEqual(cats.map { $0.id }, ["3", "4"])

        let live = Xtream.parseItems(Data(#"[{"name":"One","stream_id":10,"stream_icon":"http://x/l.png","category_id":"3","tv_archive":1,"epg_channel_id":"one.tv"},{"name":"NoId"},{"stream_id":"11","name":"Two","stream_icon":"","category_id":4}]"#.utf8),
                                     kind: .live, account: account, playlist: playlist)
        XCTAssertEqual(live.count, 2)
        XCTAssertEqual(live[0].url, "http://host.tld:8080/live/user/p%40ss%2Fword/10.m3u8")
        XCTAssertEqual(live[0].logo, "http://x/l.png")
        XCTAssertTrue(live[0].hasArchive)
        XCTAssertEqual(live[0].epgChannelID, "one.tv")
        XCTAssertNil(live[1].logo)
        XCTAssertEqual(live[1].categoryID, "4")

        let movies = Xtream.parseItems(Data(#"[{"name":"Film (1999)","stream_id":"5","container_extension":"mkv","rating":"7.5"},{"name":"Other","stream_id":6,"year":"2010","rating":0}]"#.utf8),
                                       kind: .movie, account: account, playlist: playlist)
        XCTAssertEqual(movies[0].year, "1999")
        XCTAssertEqual(movies[0].rating, 7.5)
        XCTAssertEqual(movies[0].containerExt, "mkv")
        XCTAssertEqual(movies[1].year, "2010")
        XCTAssertNil(movies[1].rating)

        let series = Xtream.parseItems(Data(#"[{"name":"Show","series_id":9,"cover":"https://x/c.jpg"}]"#.utf8),
                                       kind: .series, account: account, playlist: playlist)
        XCTAssertEqual(series[0].streamID, "9")
        XCTAssertNil(series[0].url)
    }

    func testSeriesInfoAsObjectAndAsList() {
        let asObject = #"{"info":{"plot":"About","cover":"http://x/c.jpg"},"episodes":{"2":[{"id":"21","episode_num":1,"title":"B","container_extension":"mp4"}],"1":[{"id":"12","episode_num":"2","title":"A2","container_extension":"mkv","info":{"duration_secs":1500}},{"id":11,"episode_num":1,"season":1}]}}"#
        let d = Xtream.parseSeriesInfo(Data(asObject.utf8), account: account)
        XCTAssertEqual(d.plot, "About")
        XCTAssertEqual(d.seasons, [1, 2])
        XCTAssertEqual(d.episodes(inSeason: 1).map { $0.id }, ["11", "12"])
        XCTAssertEqual(d.episodes(inSeason: 1)[0].title, "S1 E1")
        XCTAssertEqual(d.episodes(inSeason: 1)[1].durationSecs, 1500)
        XCTAssertEqual(d.episodes(inSeason: 2)[0].url, "http://host.tld:8080/series/user/p%40ss%2Fword/21.mp4")

        let asList = #"{"episodes":[[{"id":"1","episode_num":1}],[{"id":"2","episode_num":1}]]}"#
        XCTAssertEqual(Xtream.parseSeriesInfo(Data(asList.utf8), account: account).seasons, [1, 2])
        XCTAssertTrue(Xtream.parseSeriesInfo(Data("nope".utf8), account: account).episodes.isEmpty)
    }

    func testEPGDecodesBase64() {
        let title = Data("Abendschau".utf8).base64EncodedString()
        let json = #"{"epg_listings":[{"id":"1","title":"\#(title)","description":"","start_timestamp":"2000","stop_timestamp":"3000"},{"title":"\#(title)","start_timestamp":1000,"stop_timestamp":2000},{"title":"\#(title)","start_timestamp":5,"stop_timestamp":5}]}"#
        let e = Xtream.parseEPG(Data(json.utf8))
        XCTAssertEqual(e.count, 2)
        XCTAssertEqual(e[0].title, "Abendschau")
        XCTAssertEqual(e[0].start, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(e[1].end, Date(timeIntervalSince1970: 3000))
    }
}

final class M3UTests: XCTestCase {
    private let playlist = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    func testParsesAttributesAndNamesWithCommas() {
        let text = """
        \u{FEFF}#EXTM3U url-tvg="http://epg.tld/guide.xml"
        #EXTINF:-1 tvg-id="one.tv" tvg-logo="http://x/logo.png" group-title="News, World",One, Two and Three
        http://host/live/u/p/1.ts
        #EXTINF:-1,Plain
        #EXTGRP:Extra
        http://host/plain.m3u8

        #EXTINF:-1 tvg-name="Named" group-title="Movies",
        http://host/movie/u/p/5.mkv
        not a link
        http://host/bare/stream
        """
        let (entries, epg) = M3UParser.parse(text)
        XCTAssertEqual(epg, "http://epg.tld/guide.xml")
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].name, "One, Two and Three")
        XCTAssertEqual(entries[0].group, "News, World")
        XCTAssertEqual(entries[0].logo, "http://x/logo.png")
        XCTAssertEqual(entries[0].tvgID, "one.tv")
        XCTAssertEqual(entries[1].name, "Plain")
        XCTAssertEqual(entries[1].group, "Extra")
        XCTAssertEqual(entries[2].name, "Named")
        XCTAssertEqual(entries[3].name, "stream")
        XCTAssertEqual(entries[3].group, "")
    }

    func testKindsAndSeriesGrouping() {
        XCTAssertEqual(M3ULibrary.kind(ofURL: "http://h/live/u/p/1.ts", name: "x"), .live)
        XCTAssertEqual(M3ULibrary.kind(ofURL: "http://h/movie/u/p/1.mkv", name: "x"), .movie)
        XCTAssertEqual(M3ULibrary.kind(ofURL: "http://h/series/u/p/1.mkv", name: "x"), .series)
        XCTAssertEqual(M3ULibrary.kind(ofURL: "http://h/files/a.mp4", name: "Show S01E02"), .series)
        XCTAssertEqual(M3ULibrary.kind(ofURL: "http://h/files/a.mp4?token=1", name: "Film"), .movie)
        XCTAssertEqual(M3ULibrary.kind(ofURL: "http://h/stream", name: "Channel"), .live)

        let ep = M3ULibrary.episode(in: "The Show - S02 E05 - Title")
        XCTAssertEqual(ep?.series, "The Show")
        XCTAssertEqual(ep?.season, 2)
        XCTAssertEqual(ep?.number, 5)
        XCTAssertNil(M3ULibrary.episode(in: "Just a film"))

        let entries = [
            M3UEntry(name: "Ch 1", url: "http://h/live/u/p/1.ts", group: "News"),
            M3UEntry(name: "Film", url: "http://h/movie/u/p/2.mp4", group: "Movies"),
            M3UEntry(name: "Show S01E01", url: "http://h/series/u/p/3.mp4", group: "Shows"),
            M3UEntry(name: "Show S01E02", url: "http://h/series/u/p/4.mp4", group: "Shows"),
            M3UEntry(name: "Other S02E01", url: "http://h/series/u/p/5.mp4", group: "Shows")
        ]
        let lib = M3ULibrary.build(entries, playlist: playlist)
        XCTAssertEqual(lib.items[.live]?.count, 1)
        XCTAssertEqual(lib.items[.movie]?.count, 1)
        XCTAssertEqual(lib.items[.series]?.map { $0.name }, ["Show", "Other"])
        XCTAssertEqual(lib.categories[.series]?.map { $0.name }, ["Shows"])
        let show = lib.items[.series]![0]
        XCTAssertEqual(lib.episodes[show.id]?.map { $0.number }, [1, 2])
        XCTAssertEqual(lib.episodes[lib.items[.series]![1].id]?.first?.season, 2)
    }
}

final class PlaybackTests: XCTestCase {
    func testFileExtension() {
        XCTAssertEqual(Playback.fileExtension(of: "http://h/a/b.MKV?x=1.ts"), "mkv")
        XCTAssertNil(Playback.fileExtension(of: "http://h/a/b"))
        XCTAssertNil(Playback.fileExtension(of: "http://h.tld"))
        XCTAssertTrue(Playback.isNativelyPlayable("http://h/a.m3u8"))
        XCTAssertTrue(Playback.isNativelyPlayable("http://h/stream"))
        XCTAssertFalse(Playback.isNativelyPlayable("http://h/a.mkv"))
        XCTAssertFalse(Playback.isNativelyPlayable("http://h/a.ts"))
    }

    func testHlsVariantOfXtreamLiveAddresses() {
        XCTAssertEqual(Playback.hlsVariant(ofLive: "http://h:80/live/u/p/12.ts"), "http://h:80/live/u/p/12.m3u8")
        XCTAssertEqual(Playback.hlsVariant(ofLive: "http://h:80/u/p/12"), "http://h:80/live/u/p/12.m3u8")
        XCTAssertEqual(Playback.hlsVariant(ofLive: "http://h:80/u/p/12.ts"), "http://h:80/live/u/p/12.m3u8")
        XCTAssertNil(Playback.hlsVariant(ofLive: "http://h/some/other/path/x.ts"))
        XCTAssertNil(Playback.hlsVariant(ofLive: "http://h/u/p/name"))
        XCTAssertNil(Playback.hlsVariant(ofLive: "http://h/live/u/p/12.m3u8"))
    }

    func testCandidates() {
        XCTAssertEqual(Playback.candidates(for: "http://h/live/u/p/1.ts", kind: .live), ["http://h/live/u/p/1.m3u8"])
        XCTAssertEqual(Playback.candidates(for: "http://h/x.m3u8", kind: .live), ["http://h/x.m3u8"])
        XCTAssertEqual(Playback.candidates(for: "http://h/u/p/1", kind: .live), ["http://h/live/u/p/1.m3u8", "http://h/u/p/1"])
        XCTAssertEqual(Playback.candidates(for: "http://h/movie/u/p/1.mkv", kind: .movie), [])
        XCTAssertEqual(Playback.candidates(for: "http://h/movie/u/p/1.mp4", kind: .movie), ["http://h/movie/u/p/1.mp4"])
        XCTAssertEqual(Playback.vlcURL(for: "http://h/a b.mkv")?.absoluteString,
                       "vlc-x-callback://x-callback-url/stream?url=http%3A%2F%2Fh%2Fa%20b.mkv")
    }

    func testSearchIgnoresCaseAndAccents() {
        let items = ["Ördek Avı", "TRT 1 HD", "Das Erste", "trt haber"].enumerated().map {
            MediaItem(id: "\($0.offset)", kind: .live, name: $0.element)
        }
        XCTAssertEqual(Search.filter(items, query: "ordek").map { $0.name }, ["Ördek Avı"])
        XCTAssertEqual(Search.filter(items, query: "trt").map { $0.name }, ["TRT 1 HD", "trt haber"])
        XCTAssertEqual(Search.filter(items, query: "hd trt").map { $0.name }, ["TRT 1 HD"])
        XCTAssertEqual(Search.filter(items, query: "avi").map { $0.name }, ["Ördek Avı"])
        XCTAssertTrue(Search.filter(items, query: "  ").isEmpty)
    }

    func testStableIDIsStable() {
        XCTAssertEqual(StableID.hash("abc"), "e71fa2190541574b")
        XCTAssertEqual(StableID.hash("").count, 16)
    }
}
