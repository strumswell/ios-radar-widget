//
//  APIClient.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import CoreLocation

enum AlertResponse {
    case brightsky(Operations.getAlerts.Output.Ok.Body.jsonPayload)
    case canadian(Operations.getCanadianWeatherAlerts.Output.Ok.Body.jsonPayload)
}

// TODO: Caching for API results
class APIClient {
    var openMeteo: Client
    var openMeteoAqi: Client
    var openMeteoGeo: Client
    var brightsky: Client
    var canadaWeather: Client
    var settingService: SettingService

    init () {
        openMeteo = APIClient.get(url: try! Servers.server1())
        openMeteoAqi = APIClient.get(url: try! Servers.server2())
        openMeteoGeo = APIClient.get(url: try! Servers.server3())
        brightsky = APIClient.get(url: try! Servers.server4())
        canadaWeather = APIClient.get(url: try! Servers.server5())
        settingService = SettingService()
    }
    
    class func get(url: URL) -> Client {
        return Client(
            serverURL: url,
            transport: URLSessionTransport(),
            middlewares: [
                CachingMiddleware(cacheTime: 60),
                RetryingMiddleware(
                    signals: [.code(429), .range(500..<600), .errorThrown],
                    policy: .upToAttempts(count: 3),
                    delay: .constant(seconds: 1)
                )
            ]
        )
    }
    
    func getForecast(coordinates: CLLocationCoordinate2D, forecastDays: Operations.getForecast.Input.Query.forecast_daysPayload? = ._14) async throws -> Operations.getForecast.Output.Ok.Body.jsonPayload {
        let fallbackForecast: Operations.getForecast.Output.Ok.Body.jsonPayload = .init(latitude: coordinates.latitude, longitude: coordinates.longitude, current: .init(cloudcover: 0.0, time: 0.0, temperature: 0.0, windspeed: 0.0, wind_direction_10m: 0.0, weathercode: 0.0))
        
        var query: Operations.getForecast.Input.Query = .init(
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            hourly: [.temperature_2m, .apparent_temperature, .precipitation, .weathercode, .cloudcover, .windspeed_10m, .windspeed_80m, .windspeed_120m, .windspeed_180m, .winddirection_10m, .precipitation_probability, .is_day, .relativehumidity_2m, .pressure_msl, .soil_temperature_0cm, .soil_temperature_6cm, .soil_temperature_18cm, .soil_temperature_54cm, .soil_moisture_0_1cm, .soil_moisture_1_3cm, .soil_moisture_3_9cm, .soil_moisture_9_27cm, .soil_moisture_27_81cm, .et0_fao_evapotranspiration],
            daily: [.precipitation_probability_max, .precipitation_sum, .sunrise, .sunset, .temperature_2m_max, .temperature_2m_min, .weathercode],
            current: [.cloudcover, .temperature, .wind_direction_10m, .weathercode, .windspeed, .precipitation, .is_day],
            temperature_unit: Operations.getForecast.Input.Query.temperature_unitPayload(rawValue: settingService.settings?.temperatureUnit ?? "celsius"), 
            windspeed_unit: Operations.getForecast.Input.Query.windspeed_unitPayload(rawValue: settingService.settings?.windSpeedUnit ?? "kmh"),
            precipitation_unit: Operations.getForecast.Input.Query.precipitation_unitPayload(rawValue: settingService.settings?.precipitationUnit ?? "mm"),
            timeformat: .unixtime,
            timezone: "auto",
            forecast_days: forecastDays
        )
        
        // Open Meteo does not have a model for Spain and falls back to a very unreliable mix of models
        // Pin the DWD ICON model for Spain and Portugal
        if coordinates.country() == .spain || coordinates.country() == .portugal {
            query.models = .icon_seamless
            query.forecast_days = ._7
        }
                
        let response = try await openMeteo.getForecast(.init(query: query))
        
        switch response {
        case let .ok(response):
            switch response.body {
            case .json(let result):
                return result
            }
        case .badRequest(_):
            return fallbackForecast
        case .undocumented(statusCode: _, _):
            return fallbackForecast
        }
    }
    
    func getAirQuality(coordinates: CLLocationCoordinate2D) async throws -> Operations.getAirQuality.Output.Ok.Body.jsonPayload {
        let fallbackForecast: Operations.getAirQuality.Output.Ok.Body.jsonPayload = .init(latitude: 0, longitude: 0)
        
        let response = try await openMeteoAqi.getAirQuality(.init(
            query: .init(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude,
                timezone: "auto", timeformat: .unixtime, forecast_days: ._1,
                hourly: [.european_aqi, .european_aqi_no2, .european_aqi_o3, .european_aqi_pm10, .european_aqi_pm10, .european_aqi_pm2_5, .european_aqi_so2, .uv_index]
            )
        ))
        
        switch response {
        case let .ok(response):
            switch response.body {
            case .json(let result):
                return result
            }
        case .undocumented(statusCode: _, _):
            return fallbackForecast
        }
    }
    
    func getAlerts(coordinates: CLLocationCoordinate2D) async throws -> AlertResponse {
        if isCanadianLocation(coordinates) {
            return try await getCanadianWeatherAlerts(coordinates: coordinates)
        } else {
            return try await getBrightskyAlerts(coordinates: coordinates)
        }
    }

    private func isCanadianLocation(_ coordinates: CLLocationCoordinate2D) -> Bool {
        // Rough bounding box for Canada
        return coordinates.latitude >= 41.0 && coordinates.latitude <= 84.0 &&
               coordinates.longitude >= -141.0 && coordinates.longitude <= -52.0
    }

    private func getBrightskyAlerts(coordinates: CLLocationCoordinate2D) async throws -> AlertResponse {
        let response = try await brightsky.getAlerts(.init(
            query: .init(
                lat: coordinates.latitude,
                lon: coordinates.longitude
            )
        ))
        
        switch response {
        case let .ok(response):
            switch response.body {
            case .json(let result):
                return .brightsky(result)
            }
        case .undocumented:
            return .brightsky(.init())
        }
    }

    private func getCanadianWeatherAlerts(coordinates: CLLocationCoordinate2D) async throws -> AlertResponse {
        let response = try await canadaWeather.getCanadianWeatherAlerts(.init(
            path: .init(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude
            )
        ))
        
        switch response {
        case let .ok(response):
            switch response.body {
            case .json(let result):
                return .canadian(result)
            }
        case .undocumented:
            return .canadian([])
        }
    }
    
    func getGeocodeSearchResult(name: String) async throws -> Components.Schemas.SearchResponse {
        let appLanguage = Locale.current.language.languageCode?.identifier ?? "de"
        let response = try await openMeteoGeo.search(.init(
            query: .init(name: name, language: Operations.search.Input.Query.languagePayload(rawValue: appLanguage))
        ))
        switch response {
        case let .ok(response):
            switch response.body {
            case .json(let result):
                return result
            }
        case .undocumented:
            return .init()
        }
    }
    
    func getRainRadar(coordinates: CLLocationCoordinate2D) async throws -> Components.Schemas.RadarResponse {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        let iso8601String = formatter.string(from: Date())
        let response = try await brightsky.getRainRadar(.init(
            query: .init(date: iso8601String, lat: coordinates.latitude, lon: coordinates.longitude, distance: 0, tz: "Europe/Berlin", format: .plain)
        ))
        switch response {
        case let .ok(response):
            switch response.body {
            case .json(let result):
                return result
            }
        case .undocumented:
            return .init()
        }
    }
}
