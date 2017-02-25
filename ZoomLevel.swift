//
//  ZoomLevel.swift
//
//  Created by Cody Fazio on 2/24/17.
//
//
/* A Swift Implementation of MKMapViewZoom, an Objective C category for 
 adding zoom level support. MKMapViewZoom was written by Troy Brant,
 and is found here: 
 http://troybrant.net/blog/2010/01/mkmapview-and-zoom-levels-a-visual-guide/
 The Objective C category is also hosted here: 
 https://github.com/johndpope/MKMapViewZoom
 */
 

import MapKit
import Foundation

let MERCATOR_OFFSET = 268435456.0
let MERCATOR_RADIUS = 85445659.44705395

extension MKMapView {
    
    //MARK: Public Methods
    public func setCenterCoordinate(fromCoordinate coordinate: CLLocationCoordinate2D,
                                    atZoomLevel zoomLevel: Int,
                                    animated: Bool) {
        
        // Clamp large numbers to 28
        let tempZoom = UInt(min(zoomLevel, 28))
        
        // Compute region with zoom
        let span = coordinateSpan(fromCenterCoordinate: coordinate, zoomLevel: tempZoom)
        let region = MKCoordinateRegionMake(coordinate, span)

        // Refresh the region
        self.setRegion(region, animated: animated)
        
    }
    
    /* MapView cannot display tiles that cross the pole (as these would involve
     wrapping the map from top to bottom, something that a Mercator projection just 
     cannot do). */
    public func coordinateRegion(forCenterCoordinate coordinate: CLLocationCoordinate2D,
                                 atZoomLevel zoomLevel: UInt) -> MKCoordinateRegion {
        
        
        var tempCoordinate = coordinate
        
        // Clamp lat/long values to appropriate ranges
        tempCoordinate.latitude = min(max(-90.0, tempCoordinate.latitude), 90.0)
        tempCoordinate.longitude = fmod(tempCoordinate.longitude, 180.0)
        
        // Convert center coordinate to pixel space
        let centerPixelX = self.toPixelSpaceX(fromLongitude: tempCoordinate.longitude)
        let centerPixelY = self.toPixelSpaceY(fromLatitude: tempCoordinate.latitude)
        
        // Determine the scale value from the zoom level
        let zoomExponent = Double(20 - zoomLevel)
        let zoomScale = pow(2.0, zoomExponent)
        
        // Scale the map’s size in pixel space
        let mapSizeInPixels = self.bounds.size
        let scaledMapWidth = Double(mapSizeInPixels.width) * zoomScale
        let scaledMapHeight = Double(mapSizeInPixels.height) * zoomScale
        
        // Calculate position of the top-left pixel
        let topLeftPixelX = centerPixelX - Double((scaledMapWidth / 2))
        
        // Find delta between left and right longitudes
        let minLong: CLLocationDegrees = self.toLongitude(fromPixelSpaceX: topLeftPixelX)
        let maxLong: CLLocationDegrees = self.toLongitude(fromPixelSpaceX: topLeftPixelX + scaledMapWidth)
        let longitudeDelta = maxLong - minLong

        // If we’re at a pole, then calculate the distance from the pole towards the equator
        // as MKMapView doesn’t like drawing boxes over the poles
        var topPixelY = centerPixelY - (scaledMapHeight/2)
        var bottomPixelY = centerPixelY + (scaledMapHeight/2)
        var adjustedCenterPoint = false
        if (topPixelY > MERCATOR_OFFSET * 2) {
            topPixelY = centerPixelY - scaledMapHeight
            bottomPixelY = MERCATOR_OFFSET * 2
            adjustedCenterPoint = true
        }
        
        // Find delta between top and bottom latitudes
        let minLat: CLLocationDegrees = self.toLatitude(fromPixelSpaceY: topPixelY)
        let maxLat: CLLocationDegrees = self.toLatitude(fromPixelSpaceY: bottomPixelY)
        let latitudeDelta = (maxLat - minLat) * -1
        
        // Create and return the lat/long span
        let span = MKCoordinateSpanMake(latitudeDelta, longitudeDelta)
        var region = MKCoordinateRegionMake(coordinate, span)

        // Again MKMapView doesn’t like drawing boxes over the poles
        // so we just adjust the center coordinate to the center of the resulting region
        if adjustedCenterPoint {
            region.center.latitude = self.toLatitude(fromPixelSpaceY: (bottomPixelY + topPixelY)/2.0)
        }
        
        return region
    }
    
    public func zoomLevel() -> Int {
        let centerPixelX = toPixelSpaceX(fromLongitude: region.center.longitude)
        let topLeftPixelX = toPixelSpaceX(
            fromLongitude: region.center.longitude - (region.span.longitudeDelta/2))
        
        let scaledMapWidth = (centerPixelX - topLeftPixelX) * 2
        let mapSizeInPixels = bounds.size
        let zoomScale = scaledMapWidth/Double(mapSizeInPixels.width)
        let zoomExponent = (log(zoomScale) / log(2.0))
        let zoomLevel = Int(20 - zoomExponent)
        
        return zoomLevel
    }
    

    //MARK: Private Methods
    //MARK: Map Conversion Methods
    private func toPixelSpaceX(fromLongitude longitude: Double) -> Double {
        return round(MERCATOR_OFFSET + MERCATOR_RADIUS * longitude * M_PI / 180.0)
    }
    
    private func toPixelSpaceY(fromLatitude latitude: Double) -> Double {
        if latitude == 90.0 {
            return 0
        } else if latitude == -90.0 {
            return MERCATOR_OFFSET * 2
        } else {
            let innerCalc = (1 + sinf(Float(latitude * M_PI / 180.0)))
            let outerCalc = (1 - sinf(Float(latitude * M_PI / 180.0)))
            let composedCalc = Double(logf(innerCalc / outerCalc))
           
            return round(MERCATOR_OFFSET - MERCATOR_RADIUS * composedCalc/2)
        }
    }
    
    private func toLongitude(fromPixelSpaceX pixelX: Double) -> Double {
        return (((round(pixelX) - MERCATOR_OFFSET) / MERCATOR_RADIUS) * 180.0 / M_PI)
    }
    
    private func toLatitude(fromPixelSpaceY pixelY: Double) -> Double {
        let innerCalc = atan(exp((round(pixelY) - MERCATOR_OFFSET) / MERCATOR_RADIUS))
        return (M_PI / 2.0 - 2.0 * innerCalc) * 180 / M_PI
    }
    
    //MARK: Helper Methods
    
    private func coordinateSpan(fromCenterCoordinate coordinate: CLLocationCoordinate2D, zoomLevel: UInt) -> MKCoordinateSpan {
        
        // Convert center coordinate to pixel space
        let centerPixelX = self.toPixelSpaceX(fromLongitude: centerCoordinate.longitude)
        let centerPixelY = self.toPixelSpaceY(fromLatitude: centerCoordinate.latitude)
        
        // Determine the scale value from the zoom level
        let zoomExponent = Double(20 - zoomLevel)
        let zoomScale = Double(pow(2.0, zoomExponent))
        
        // Scale the map’s size in pixel space
        let mapSizeInPixels = self.bounds.size
        let scaledMapWidth = Double(mapSizeInPixels.width) * zoomScale
        let scaledMapHeight = Double(mapSizeInPixels.height) * zoomScale
        
        // Calculate position of the top-left pixel
        let topLeftPixelX = centerPixelX - Double((scaledMapWidth / 2))
        let topLeftPixelY = centerPixelY - Double((scaledMapHeight / 2))
       
        // Find delta between left and right longitudes
        let minLong: CLLocationDegrees = self.toLongitude(fromPixelSpaceX: topLeftPixelX)
        let maxLong: CLLocationDegrees = self.toLongitude(fromPixelSpaceX: topLeftPixelX + scaledMapWidth)
        let longitudeDelta = maxLong - minLong
        
        // Find delta between top and bottom latitudes
        let minLat: CLLocationDegrees = self.toLatitude(fromPixelSpaceY: topLeftPixelY)
        let maxLat: CLLocationDegrees = self.toLatitude(fromPixelSpaceY: topLeftPixelY + scaledMapHeight)
        let latitudeDelta = (maxLat - minLat) * -1
        
        // Create and return span
        let span = MKCoordinateSpanMake(latitudeDelta, longitudeDelta)
        return span
    }
}
