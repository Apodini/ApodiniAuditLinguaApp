//
// This source file is part of the Apodini open source project
//
// SPDX-FileCopyrightText: 2019-2021 Paul Schmiedmayer and the Apodini project authors (see CONTRIBUTORS.md) <paul.schmiedmayer@tum.de>
//
// SPDX-License-Identifier: MIT
//

import XCTest
@testable import BadLinguaWebService
@testable import ImprovedLinguaWebService
@testable import Apodini
import XCTApodiniNetworking
import ApodiniHTTPProtocol
import XCTApodini
import Shared
@testable import ApodiniAudit

/// Tests that the report generated by ApodiniAudit for the ``BadLinguaWebService`` lists the correct findings for the checkable best practices.
final class CheckableBPTests: XCTApodiniTest {
    static var audits: [Audit]!
    
    override class func setUp() {
        // Run the AuditSetupCommand to install NLTK. It doesn't matter which WebService we specify.
        let app = Application()
        let commandType = AuditSetupNLTKCommand<ImprovedLinguaWebService>.self
        let command = commandType.init()
        do {
            try command.run(app: app)
            print("Installed requirements!")
        } catch {
            print("Could not install requirements: \(error)")
        }
        
        let runcommandtype = AuditRunCommand<BadLinguaWebService>.self
        var runcommand = runcommandtype.init()
        
        do {
            audits = try getAuditsForAuditRunCommand(&runcommand).filter { $0.findings.count > 0 }
        } catch {
            fatalError("could not get audits: \(error)")
        }
    }
    
    func testDeleteReturnTypeFinding() throws {
        let finding = try CheckableBPTests.getSingleFindingFromSingleAudit(
            bptype: EndpointHasComplexReturnType.self,
            findingType: ReturnTypeFinding.self,
            endpointPath: "/en/dictionary/entries/{entryId}",
            handlerName: "DeleteDictionaryEntryHandler"
        )
        XCTAssertEqual(finding, .hasPrimitiveReturnType(.delete))
    }
    
    func testTooManyParamsFinding() throws {
        let finding = try CheckableBPTests.getSingleFindingFromSingleAudit(
            bptype: ReasonableParameterCount.self,
            findingType: ParameterCountFinding.self,
            endpointPath: "/en/dictionary/entries",
            handlerName: "SearchDictionaryHandler"
        )
        XCTAssertEqual(finding, .tooManyParameters(count: 12))
    }
    
    func testETagSuggestion() throws {
        let finding = try CheckableBPTests.getSingleFindingFromSingleAudit(
            bptype: EncourageETags.self,
            findingType: ETagsFinding.self,
            endpointPath: "/en/lectures/{lectureId}/image/{imageId}",
            handlerName: "GetImageHandler"
        )
        XCTAssertEqual(finding, .cacheableBlob)
    }
    
    func testPluralDetection() throws {
        let finding = CheckableBPTests.getFindings(
            PluralSegmentForStoresAndCollections.self,
            findingType: BadCollectionSegmentName.self,
            endpointPath: "/en/lectures/{lectureId}/image/{imageId}",
            handlerName: "GetImageHandler"
        )
        
        XCTAssertEqual(finding.count, 1)
        let fndg = try XCTUnwrap(finding.first)
        XCTAssertEqual(fndg, .nonPluralBeforeParameter("image"))
    }
    
    func testCapitalLetterDetection() throws {
        let finding = CheckableBPTests.getFindings(
            LowercaseURLPathSegments.self,
            findingType: LowercasePathSegmentsFinding.self,
            endpointPath: "/en/getFavoriteLectures",
            handlerName: "GetFavoriteLecturesHandler"
        )
        
        XCTAssertEqual(finding.count, 1)
        let fndg = try XCTUnwrap(finding.first)
        XCTAssertEqual(fndg, .uppercaseCharacterFound(segment: "getFavoriteLectures"))
    }
    
    func testCRUDVerbDetection() throws {
        let finding = CheckableBPTests.getFindings(
            NoCRUDVerbsInURLPathSegments.self,
            findingType: URLCRUDVerbsFinding.self,
            endpointPath: "/en/getFavoriteLectures",
            handlerName: "GetFavoriteLecturesHandler"
        )
        
        XCTAssertEqual(finding.count, 1)
        let fndg = try XCTUnwrap(finding.first)
        XCTAssertEqual(fndg, .crudVerbFound(segment: "getFavoriteLectures"))
    }
    
    func testNoFindingsForImprovedWebService() {
        let runcommandtype = AuditRunCommand<ImprovedLinguaWebService>.self
        var runcommand = runcommandtype.init()
        
        do {
            let nonEmptyAudits = try CheckableBPTests.getAuditsForAuditRunCommand(&runcommand).filter { $0.findings.count > 0 }
            XCTAssertEqual(nonEmptyAudits.count, 0)
        } catch {
            fatalError("could not get audits: \(error)")
        }
    }
    
    private static func getSingleFindingFromSingleAudit<F: Finding>(
        bptype: BestPractice.Type,
        findingType: F.Type,
        endpointPath: String,
        handlerName: String,
        webServiceString: String = "BadLinguaWebService"
    ) throws -> F {
        XCTAssertEqual(audits.count(where: { type(of: $0.bestPractice) == bptype }), 1)
        let audit = try XCTUnwrap(audits.first(where: { type(of: $0.bestPractice) == bptype }))
        XCTAssertEqual(audit.findings.count, 1)
        XCTAssertEqual(audit.endpoint.absolutePath.pathString, endpointPath)
        XCTAssertEqual(audit.endpoint.bareHandlerName(webServiceString), handlerName)
        return try XCTUnwrap(audit.findings.first) as! F
    }
    
    private static func getFindings<F: Finding>(
        _ bptype: BestPractice.Type,
        findingType: F.Type,
        endpointPath: String,
        handlerName: String,
        webServiceString: String = "BadLinguaWebService"
    ) -> [F] {
        let bpaudits = audits.filter {
            type(of: $0.bestPractice) == bptype &&
            $0.endpoint.bareHandlerName(webServiceString) == handlerName &&
            $0.endpoint.absolutePath.pathString == endpointPath
        }
        return bpaudits.flatMap {
            $0.findings.compactMap {
                $0 as? F
            }
        }
    }
    
    static func getAuditsForAuditRunCommand<T: WebService>(_ command: inout AuditRunCommand<T>) throws -> [Audit] {
        let report = try getReportForAuditRunCommand(&command)
        return report.audits
    }
    
    static func getReportForAuditRunCommand<T: WebService>(_ command: inout AuditRunCommand<T>) throws -> Report {
        command.webService = .init()
        
        let app = Application()
        try command.run(app: app)
        
        // Get the AuditInterfaceExporter
        // FUTURE We just get the first one, for now we do not consider the case of multiple exporters
        let optionalExporter = app.interfaceExporters.first { exporter in
            exporter.typeErasedInterfaceExporter is AuditInterfaceExporter
        }
        let auditInterfaceExporter = try XCTUnwrap(optionalExporter?.typeErasedInterfaceExporter as? AuditInterfaceExporter)
        
        return auditInterfaceExporter.report
    }
}
