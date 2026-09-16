import Foundation
import Testing
@testable import CodexBarCore

struct MyCoderUsageFetcherTests {
    @Test
    func `parses canonical quota response`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data("""
        {
          "success": true,
          "data": {
            "account": "louis_jeng@asus.com",
            "totalQuota": 1000,
            "availableQuota": 640
          }
        }
        """.utf8)

        let snapshot = try MyCoderUsageFetcher.parseQuota(data: data, now: now)

        #expect(snapshot.account == "louis_jeng@asus.com")
        #expect(snapshot.totalBudget == 1000)
        #expect(snapshot.availableBudget == 640)
        #expect(snapshot.usedBudget == 360)
        #expect(snapshot.updatedAt == now)
    }

    @Test
    func `parses quota aliases and string values`() throws {
        let data = Data("""
        {
          "success": true,
          "data": {
            "account": "louis_jeng@asus.com",
            "quota": "2500.5",
            "remainingQuota": "1499.25"
          }
        }
        """.utf8)

        let snapshot = try MyCoderUsageFetcher.parseQuota(data: data)

        #expect(snapshot.totalBudget == 2500.5)
        #expect(snapshot.availableBudget == 1499.25)
        #expect(snapshot.usedBudget == 1001.25)
    }

    @Test
    func `parses top level quota payload without success flag`() throws {
        let data = Data("""
        {
          "quota": {
            "account": "louis_jeng@asus.com",
            "total": "5000",
            "remaining": 3250
          }
        }
        """.utf8)

        let snapshot = try MyCoderUsageFetcher.parseQuota(data: data)

        #expect(snapshot.account == "louis_jeng@asus.com")
        #expect(snapshot.totalBudget == 5000)
        #expect(snapshot.availableBudget == 3250)
        #expect(snapshot.usedBudget == 1750)
    }

    @Test
    func `parses result payload with budget aliases`() throws {
        let data = Data("""
        {
          "success": true,
          "result": {
            "budget": 1200,
            "availableBudget": "750.5"
          }
        }
        """.utf8)

        let snapshot = try MyCoderUsageFetcher.parseQuota(data: data)

        #expect(snapshot.totalBudget == 1200)
        #expect(snapshot.availableBudget == 750.5)
        #expect(snapshot.usedBudget == 449.5)
    }

    @Test
    func `parses token usage api quota payload`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data("""
        {
          "userId": "16c101f2-4c5e-4fd7-9e83-90c26cff1632",
          "account": "louis_jeng",
          "totalQuota": 100,
          "nextTotalQuota": 100,
          "availableQuota": 87.2976895766,
          "discount": 0,
          "createdAt": "2026-05-18T09:12:28Z",
          "updatedAt": "2026-07-01T02:09:30Z"
        }
        """.utf8)

        let snapshot = try MyCoderUsageFetcher.parseQuota(data: data, now: now)

        #expect(snapshot.account == "louis_jeng")
        #expect(snapshot.totalBudget == 100)
        #expect(abs(snapshot.availableBudget - 87.2976895766) < 0.000001)
        #expect(snapshot.updatedAt == now)
    }

    @Test
    func `extracts sso token from cookie header`() {
        #expect(
            MyCoderUsageFetcher.ssoToken(fromCredentials: "foo=bar; PUBLIC_USER_SSO_TOKEN=abc.def.ghi; baz=qux")
                == "abc.def.ghi")
        #expect(MyCoderUsageFetcher.ssoToken(fromCredentials: "foo=bar; baz=qux") == nil)
        #expect(MyCoderUsageFetcher.ssoToken(fromCredentials: "") == nil)
        // Raw pasted token without cookie syntax is accepted.
        #expect(MyCoderUsageFetcher.ssoToken(fromCredentials: "abc.def.ghi") == "abc.def.ghi")
    }

    @Test
    func `extracts user id from sso token audience`() {
        // JWT payload: {"iss":"iam user access token","aud":["test-user-id"],"exp":1790139598}
        let payload = Data(#"{"iss":"iam user access token","aud":["test-user-id"],"exp":1790139598}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.\(payload).signature"

        #expect(MyCoderUsageFetcher.userId(fromSSOToken: token) == "test-user-id")
        #expect(MyCoderUsageFetcher.userId(fromSSOToken: "not.a-jwt") == nil)
    }
}
