//
//  RadarView.swift
//  Weather
//
//  Created by Philipp Bolte on 11.08.21.
//

import SwiftUI
import MapKit

struct RadarView: View {
    //@Binding var location: CLLocationCoordinate2D?
    @ObservedObject var now: NowViewModel
    @Binding var radarMetadata: WeatherMapsResponse?
    @State var cloudLayer: Bool = false
    @State var rainLayer: Bool = true
    @State var pressureLayer: Bool = false
    @State var tempLayer: Bool = false

    var body: some View {
        Text("Radar")
            .font(.system(size: 20))
            .bold()
            .foregroundColor(.white.opacity(0.8))
            .shadow(color: .white, radius: 40)
            .padding([.leading, .top, .bottom])
            .onTapGesture {
                cloudLayer = false
            }
        ZStack {
            RadarMapView(
                overlay: getOverlay(host: radarMetadata?.host ?? "", path: radarMetadata?.radar.past[radarMetadata!.radar.past.count-1].path ?? "", color: "2", options: "1_1"),
                cloudOverlay: getOverlay(host: radarMetadata?.host ?? "", path: radarMetadata?.satellite.infrared.last?.path ?? "", color: "0", options: "0_0"),
                coordinates: now.getActiveLocation(), cities: now.cs.cities, cloudLayer: cloudLayer, rainLayer: rainLayer, pressureLayer: pressureLayer, tempLayer: tempLayer)
            VStack {
                HStack {
                    Spacer()
                    Menu {
                        Button(action: {
                            cloudLayer.toggle()
                        }) {
                            if (cloudLayer) {
                                Label("Infrarot", systemImage: "checkmark")
                            } else {
                                Text("Infrarot")
                            }
                        }
                        Button(action: {
                            rainLayer.toggle()
                        }) {
                            if (rainLayer) {
                                Label("Regen", systemImage: "checkmark")
                            } else {
                                Text("Regen")
                            }
                        }
                        Button(action: {
                            tempLayer.toggle()
                        }) {
                            if (tempLayer) {
                                Label("Temperatur", systemImage: "checkmark")
                            } else {
                                Text("Temperatur")
                            }
                        }
                        Button(action: {
                            pressureLayer.toggle()
                        }) {
                            if (pressureLayer) {
                                Label("Wind & Druck", systemImage: "checkmark")
                            } else {
                                Text("Wind & Druck")
                            }
                        }
                    } label: {
                        Image(systemName: "map.fill")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.gray.opacity(0.9))
                    }
                    .frame(width: 35, height: 35)
                    .background(Color(.systemGray6).opacity(0.8))
                    .cornerRadius(5)
                }
                Spacer()
            }
            .padding(.trailing)
            .padding(.top)
        }
        .frame(height: 350, alignment: .center)
        .background(Color.black.opacity(0.2))
        .cornerRadius(10)
        .font(.system(size: 18))
        .padding([.leading, .trailing])
        .padding(.bottom, 30)
    }
}

struct RadarMapView: UIViewRepresentable {
    var overlay: MKTileOverlay
    var cloudOverlay: MKTileOverlay
    var coordinates: CLLocationCoordinate2D
    var cities: [City]
    var cloudLayer: Bool
    var rainLayer: Bool
    var pressureLayer: Bool
    var tempLayer: Bool
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RadarMapView

        init(_ parent: RadarMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKTileOverlayRenderer(overlay: overlay)
            return renderer
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        return MKMapView()
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        let overlays = mapView.overlays
        let hour = Calendar.current.component(.hour, from: Date())
        
        mapView.removeAnnotations(mapView.annotations)

        for city in self.cities {
            if (city.selected) {
                let selectedCity = MKPointAnnotation()
                selectedCity.title = city.label
                selectedCity.coordinate = CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
                mapView.addAnnotation(selectedCity)
                break;
            }
        }


        mapView.delegate = context.coordinator
        mapView.overrideUserInterfaceStyle = .dark
        mapView.showsScale = true
        mapView.removeOverlays(overlays)
        if (pressureLayer) {
            let overlay = MKTileOverlay(urlTemplate: "https://services.meteored.com/img/tiles/cep010/{z}/{x}/{y}/0\(String(format: "%02d",hour-2))_prsvie.png")
            mapView.addOverlay(overlay)
            //https://services.meteored.com/img/tiles/cep010/6/31/21/014_temp2m@2x.png
        }
        if (tempLayer) {
            let overlay = MKTileOverlay(urlTemplate: "https://services.meteored.com/img/tiles/cep010/{z}/{x}/{y}/0\(String(format: "%02d",hour-2))_temp2m.png")
            mapView.addOverlay(overlay)
        }
        if (cloudLayer) {
            mapView.addOverlay(cloudOverlay)
        }
        if (rainLayer) {
            mapView.addOverlay(overlay)
        }

        
        let coordinateRegion = MKCoordinateRegion(center: coordinates, latitudinalMeters: 130000, longitudinalMeters: 130000)
        
        mapView.setRegion(coordinateRegion, animated: false)
        mapView.showsUserLocation = true
    }
}


func getOverlay(host: String, path: String, color: String, options: String) -> MKTileOverlay {
    let template = "\(host)\(path)/256/{z}/{x}/{y}/\(color)/\(options).png"
    let overlay = MKTileOverlay(urlTemplate:template)
    return overlay
}
