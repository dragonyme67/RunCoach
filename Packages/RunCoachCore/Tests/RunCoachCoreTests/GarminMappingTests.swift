import XCTest
@testable import RunCoachCore

/// Fixtures synthétiques : structure des réponses réelles relevée le 2026-11-13, valeurs inventées,
/// coordonnées au milieu de l'Atlantique (ARCHITECTURE.md §9.4).
final class GarminMappingTests: XCTestCase {
    static let activitiesJSON = #"""
    [
      {"activityId": 10000000001, "activityName": "Footing synthétique",
       "startTimeLocal": "2026-11-10 07:12:00", "startTimeGMT": "2026-11-10 06:12:00", "beginTimestamp": 1794291120000,
       "activityType": {"typeId": 1, "typeKey": "running", "parentTypeId": 17},
       "distance": 5012.4, "duration": 1950.2, "movingDuration": 1932.0, "elapsedDuration": 1990.0,
       "averageSpeed": 2.57, "maxSpeed": 3.4, "averageHR": 151.0, "maxHR": 172.0,
       "averageRunningCadenceInStepsPerMinute": 164.2, "elevationGain": 31.0, "elevationLoss": 29.0,
       "calories": 402.0, "aerobicTrainingEffect": 3.1, "anaerobicTrainingEffect": 0.0, "activityTrainingLoad": 88.5,
       "minTemperature": 14.0, "maxTemperature": 22.0, "locationName": "Nulle part", "hasPolyline": true,
       "hrTimeInZone_1": 120.0, "hrTimeInZone_2": 600.0, "hrTimeInZone_3": 900.0, "hrTimeInZone_4": 330.0, "hrTimeInZone_5": 0.0,
       "splitSummaries": [{"splitType": "RWD_RUN", "distance": 5000.0}], "userRoles": ["x"], "unknownFutureField": {"a": 1}},
      {"activityId": 10000000002, "activityName": "Renfo", "startTimeGMT": "2026-11-09 18:00:00",
       "activityType": {"typeKey": "strength_training"}, "duration": 1800.0, "averageHR": 110.4, "hasPolyline": false},
      {"activityName": "Sans identifiant", "duration": 10.0, "startTimeGMT": "2026-11-08 10:00:00"}
    ]
    """#

    func testActivityListDecodesAndMaps() throws {
        let dtos = try JSONDecoder().decode([ActivityDTO].self, from: Data(Self.activitiesJSON.utf8))
        let activities = dtos.compactMap(ImportedActivity.init)
        XCTAssertEqual(activities.count, 2, "l'activité sans identifiant est ignorée")

        let run = activities[0]
        XCTAssertEqual(run.garminActivityId, 10000000001)
        XCTAssertEqual(run.startDate, Date(timeIntervalSince1970: 1_794_291_120))
        XCTAssertEqual(run.dayKey, "2026-11-10")
        XCTAssertEqual(run.activityType, "running")
        XCTAssertEqual(run.distanceM, 5012.4)
        XCTAssertEqual(run.avgHR, 151)
        XCTAssertEqual(run.avgCadenceSpm, 164.2)
        XCTAssertEqual(run.avgTemperatureC, 18)
        XCTAssertEqual(run.garminLoad, 88.5)
        XCTAssertEqual(run.hrZoneSeconds, [120, 600, 900, 330, 0])
        XCTAssertTrue(run.hasTrack)

        let strength = activities[1]
        XCTAssertEqual(strength.activityType, "strength_training")
        XCTAssertEqual(strength.distanceM, 0)
        XCTAssertEqual(strength.avgHR, 110)
        XCTAssertEqual(strength.hrZoneSeconds, [])
        XCTAssertFalse(strength.hasTrack)
        XCTAssertNil(strength.avgTemperatureC)
    }

    /// Colonnes dans un ordre différent de la réponse réelle : seule la `key` compte.
    static let detailsJSON = #"""
    {"activityId": 10000000001, "measurementCount": 6,
     "metricDescriptors": [
       {"metricsIndex": 4, "key": "directLatitude", "unit": {"key": "dd", "factor": 1.0}},
       {"metricsIndex": 0, "key": "sumDistance", "unit": {"key": "meter", "factor": 100.0}},
       {"metricsIndex": 2, "key": "directHeartRate", "unit": {"key": "bpm", "factor": 1.0}},
       {"metricsIndex": 1, "key": "sumElapsedDuration", "unit": {"key": "second", "factor": 1000.0}},
       {"metricsIndex": 3, "key": "directLongitude", "unit": {"key": "dd", "factor": 1.0}},
       {"metricsIndex": 5, "key": "directRunCadence", "unit": {"key": "stepsPerMinute", "factor": 1.0}},
       {"metricsIndex": 6, "key": "directDoubleCadence", "unit": {"key": "stepsPerMinute", "factor": 1.0}},
       {"metricsIndex": 7, "key": "directElevation", "unit": {"key": "meter", "factor": 100.0}}
     ],
     "activityDetailMetrics": [
       {"metrics": [0.0, 0.0, null, -30.0, 40.0, 80.0, 160.0, 10.0]},
       {"metrics": [5.0, 2.0, 120.0, null, null, 81.0, 162.0, 11.0]},
       {"metrics": [10.0, 4.0, 130.0, -30.0001, 40.0001, 82.0, null, 12.0]},
       {"metrics": [15.0, 6.0, null, -30.0002, 40.0002, 83.0, 166.0, null]},
       {"metrics": [20.0, 8.0, 140.0, -30.0003, 40.0003]}
     ],
     "geoPolylineDTO": {"polyline": []}, "heartRateDTOs": null}
    """#

    func testTrackFromDetailsResolvesColumnsByKeyAndFillsGaps() throws {
        let dto = try JSONDecoder().decode(ActivityDetailsDTO.self, from: Data(Self.detailsJSON.utf8))
        let track = try XCTUnwrap(Track(details: dto))
        XCTAssertTrue(track.isConsistent)
        XCTAssertEqual(track.count, 4, "le relevé sans position est supprimé")
        XCTAssertEqual(track.t, [0, 4, 6, 8])
        XCTAssertEqual(track.dist, [0, 10, 15, 20])
        XCTAssertEqual(track.lat, [40, 40.0001, 40.0002, 40.0003])
        XCTAssertEqual(track.hr, [130, 130, 130, 140], "début rempli par la valeur suivante, trous par la précédente")
        XCTAssertEqual(track.cad, [160, 160, 166, 166], "cadence des deux pieds ; ligne trop courte = valeur manquante")
        XCTAssertEqual(track.ele, [10, 12, 12, 12])
        XCTAssertNil(track.speed)
    }

    func testTrackWithoutGPSIsNil() throws {
        let noGPS = #"{"metricDescriptors": [{"metricsIndex": 0, "key": "sumDistance"}], "activityDetailMetrics": [{"metrics": [1.0]}]}"#
        XCTAssertNil(Track(details: try JSONDecoder().decode(ActivityDetailsDTO.self, from: Data(noGPS.utf8))))
        XCTAssertNil(Track(details: try JSONDecoder().decode(ActivityDetailsDTO.self, from: Data("{}".utf8))))
    }

    func testRunCadenceDoubledWhenDoubleCadenceMissing() throws {
        let text = #"""
        {"metricDescriptors": [{"metricsIndex": 0, "key": "directLatitude"}, {"metricsIndex": 1, "key": "directLongitude"},
                               {"metricsIndex": 2, "key": "directTimestamp"}, {"metricsIndex": 3, "key": "sumDistance"},
                               {"metricsIndex": 4, "key": "directRunCadence"}],
         "activityDetailMetrics": [{"metrics": [1.0, 1.0, 1000000.0, 0.0, 80.0]}, {"metrics": [1.0, 1.0, 1003000.0, 9.0, 82.0]}]}
        """#
        let track = try XCTUnwrap(Track(details: try JSONDecoder().decode(ActivityDetailsDTO.self, from: Data(text.utf8))))
        XCTAssertEqual(track.cad, [160, 164])
        XCTAssertEqual(track.t, [0, 3], "temps tiré des horodatages en millisecondes")
    }

    func testDailyMetricFromSleepAndStatus() throws {
        let sleep = #"{"dailySleepDTO": {"calendarDate": "2026-11-12", "sleepTimeSeconds": 27000, "sleepScores": {"overall": {"value": 81, "qualifierKey": "GOOD"}}}, "restingHeartRate": 52, "sleepMovement": []}"#
        let status = #"""
        {"mostRecentVO2Max": {"generic": {"vo2MaxPreciseValue": 47.6, "vo2MaxValue": 48.0}},
         "mostRecentTrainingStatus": {"latestTrainingStatusData": {
            "1": {"trainingStatusFeedbackPhrase": "DETRAINING", "primaryTrainingDevice": false},
            "2": {"trainingStatusFeedbackPhrase": "PRODUCTIVE_3", "primaryTrainingDevice": true}}}}
        """#
        let metric = ImportedDailyMetric(dayKey: "2026-11-12",
                                         sleep: try JSONDecoder().decode(SleepDTO.self, from: Data(sleep.utf8)),
                                         status: try JSONDecoder().decode(TrainingStatusDTO.self, from: Data(status.utf8)))
        XCTAssertEqual(metric.sleepSeconds, 27000)
        XCTAssertEqual(metric.sleepScore, 81)
        XCTAssertEqual(metric.restingHR, 52)
        XCTAssertEqual(metric.vo2max, 47.6)
        XCTAssertEqual(metric.trainingStatus, "PRODUCTIVE_3")

        let empty = ImportedDailyMetric(dayKey: "2026-11-11", sleep: try JSONDecoder().decode(SleepDTO.self, from: Data("{}".utf8)))
        XCTAssertNil(empty.sleepSeconds)
        XCTAssertNil(empty.trainingStatus)
    }
}
