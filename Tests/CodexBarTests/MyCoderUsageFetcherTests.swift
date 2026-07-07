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
}
