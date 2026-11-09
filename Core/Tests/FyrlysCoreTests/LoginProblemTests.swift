@testable import FyrlysCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

/// Innloggingen sier hva som er galt, og prøver som en annen klient når serveren stenger ute VLC (Windows 2.1.46).
final class LoginProblemTests: XCTestCase {
    let login = Login(server: "http://iptv.example:8080", username: "kari", password: "hemmelig")
    let ok = Data(#"{"user_info": {"auth": 1, "status": "Active"}}"#.utf8)

    func failure(_ data: Data, _ status: Int) async -> SourceError? {
        let client = XtreamClient(login: login) { _ in (data, status) }
        do {
            _ = try await client.account()
            return nil
        } catch {
            return error as? SourceError
        }
    }

    func testResponses() async {
        let web = await failure(Data("<!DOCTYPE html><html><body>Velkommen</body></html>".utf8), 200)
        XCTAssertEqual(web?.failure, .notXtream)
        XCTAssertTrue(web?.message.contains("nettside") == true)
        let flare = await failure(Data("<html><title>Just a moment...</title>cloudflare</html>".utf8), 403)
        XCTAssertTrue(flare?.message.contains("Cloudflare") == true)
        let https = await failure(Data("The plain HTTP request was sent to HTTPS port".utf8), 400)
        XCTAssertTrue(https?.message.contains("https://") == true)
        let r1 = await failure(Data(), 200)
        XCTAssertEqual(r1?.failure, .rejected)
        let r2 = await failure(Data(), 404)
        XCTAssertEqual(r2?.failure, .notXtream)
        let r3 = await failure(Data(#"{"user_info": {"auth": 0}}"#.utf8), 200)
        XCTAssertEqual(r3?.failure, .wrongLogin)
    }

    func testLenientAnswers() async {
        // BOM, advarsler fra PHP foran, og auth som true, «1» eller bare status
        let bom = Data([0xEF, 0xBB, 0xBF]) + ok
        let rb = await failure(bom, 200)
        XCTAssertNil(rb)
        let warning = Data("<br />\n<b>Warning</b>: something in /var/www/x.php on line 3<br />\n".utf8) + ok
        let rw = await failure(warning, 200)
        XCTAssertNil(rw)
        let r4 = await failure(Data(#"{"user_info": {"auth": true}}"#.utf8), 200)
        XCTAssertNil(r4)
        let r5 = await failure(Data(#"{"user_info": {"auth": "1"}}"#.utf8), 200)
        XCTAssertNil(r5)
        let r6 = await failure(Data(#"{"user_info": {"status": "Active"}}"#.utf8), 200)
        XCTAssertNil(r6)
        let r7 = await failure(Data(#"{"user_info": {"auth": false}}"#.utf8), 200)
        XCTAssertEqual(r7?.failure, .wrongLogin)
    }

    func testNetworkErrors() {
        XCTAssertEqual(connectionProblem(URLError(.cannotFindHost)).failure, .unreachable)
        XCTAssertTrue(connectionProblem(URLError(.cannotFindHost)).message.contains("Fant ikke serveren"))
        XCTAssertTrue(connectionProblem(URLError(.cannotConnectToHost)).message.contains("porten"))
        XCTAssertTrue(connectionProblem(URLError(.timedOut)).message.contains("svarer ikke"))
        XCTAssertTrue(connectionProblem(URLError(.secureConnectionFailed)).message.contains("http://"))
        XCTAssertTrue(connectionProblem(URLError(.serverCertificateUntrusted)).message.contains("Sertifikatet"))
        XCTAssertEqual(connectionProblem(URLError(.networkConnectionLost)).failure, .rejected)
    }

    func testOtherClientWhenVLCIsShutOut() async throws {
        let ok = self.ok
        let result = try await XtreamClient.signIn(login) { agent in
            { _ in agent == "okhttp/4.12.0" ? (ok, 200) : (Data(), 403) }
        }
        XCTAssertEqual(result.login.userAgent, "okhttp/4.12.0")
        XCTAssertEqual(result.login.agent, "okhttp/4.12.0")
        XCTAssertEqual(result.login.id, login.id)

        // VLC virker: ingen egen klient
        let plain = try await XtreamClient.signIn(login) { _ in { _ in (ok, 200) } }
        XCTAssertNil(plain.login.userAgent)

        // feil passord: prøves ikke som andre klienter
        var asked: [String] = []
        let lock = NSLock()
        do {
            _ = try await XtreamClient.signIn(login) { agent in
                lock.lock(); asked.append(agent); lock.unlock()
                return { _ in (Data(#"{"user_info": {"auth": 0}}"#.utf8), 200) }
            }
            XCTFail("ingen feil")
        } catch {
            XCTAssertEqual((error as? SourceError)?.failure, .wrongLogin)
        }
        XCTAssertEqual(asked, [xtreamUserAgent])

        // serveren finnes ikke: heller ikke
        do {
            _ = try await XtreamClient.signIn(login) { _ in { _ in throw URLError(.cannotFindHost) } }
            XCTFail("ingen feil")
        } catch {
            XCTAssertEqual((error as? SourceError)?.failure, .unreachable)
        }

        // alle avvist: den første feilen
        do {
            _ = try await XtreamClient.signIn(login) { _ in { _ in (Data(), 403) } }
            XCTFail("ingen feil")
        } catch {
            XCTAssertEqual((error as? SourceError)?.failure, .rejected)
        }
    }

    func testOldLoginsDecodeWithoutAgent() throws {
        let old = Data(#"{"server": "http://iptv.example:8080", "username": "kari", "password": "p"}"#.utf8)
        let decoded = try JSONDecoder().decode(Login.self, from: old)
        XCTAssertNil(decoded.userAgent)
        XCTAssertEqual(decoded.agent, xtreamUserAgent)
    }

    func testChannelStatus() {
        XCTAssertNil(channelStatusProblem(200, provider: true))
        XCTAssertTrue(channelStatusProblem(403, provider: true)?.contains("avviste kanalen") == true)
        XCTAssertTrue(channelStatusProblem(404, provider: true)?.contains("404") == true)
        XCTAssertTrue(channelStatusProblem(458, provider: true)?.contains("tilkoblingene") == true)
        XCTAssertTrue(channelStatusProblem(503, provider: true)?.contains("problemer") == true)
        XCTAssertEqual(channelStatusProblem(404, provider: false), "Strømmen svarte HTTP 404.")
    }
}
