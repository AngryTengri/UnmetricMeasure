//
//  MenuDataSource.swift
//  ExampleOfiOSLiDAR
//
//  Created by TokyoYoshida on 2021/01/31.
//

import UIKit

struct MenuItem {
    let title: String
    let description: String
    let prefix: String
    
    func viewController() -> UIViewController {
        let storyboard = UIStoryboard(name: prefix, bundle: nil)
        let vc = storyboard.instantiateInitialViewController()!
        vc.title = title

        return vc
    }
}

class MenuViewModel {
    private let dataSource = [
        MenuItem (
            title: "London Bus Units",
            description: "Measure using the standard british double decker bus",
            prefix: "Measure"
        ),
        MenuItem (
            title: "American Football Fields",
            description: "Measure using NFL football field dimensions",
            prefix: "Measure"
        ),
        MenuItem (
            title: "Olympic Swimming Pools",
            description: "Measure using standard 50m Olympic pool length",
            prefix: "Measure"
        ),
        MenuItem (
            title: "Blue Whales",
            description: "Measure using the length of the largest mammal",
            prefix: "Measure"
        ),
        MenuItem (
            title: "Tennis Courts",
            description: "Measure using standard tennis court dimensions",
            prefix: "Measure"
        ),
        MenuItem (
            title: "Subway Cars",
            description: "Measure using New York subway car length",
            prefix: "Measure"
        ),
        MenuItem (
            title: "Boeing 747 Jumbo Jets",
            description: "Measure using the iconic jumbo jet wingspan",
            prefix: "Measure"
        ),
        MenuItem (
            title: "Watermelons",
            description: "Measure using average watermelon length",
            prefix: "Measure"
        ),
        MenuItem (
            title: "Toyota Prius",
            description: "Measure using the hybrid car's length",
            prefix: "Measure"
        ),
        MenuItem (
            title: "Giraffes",
            description: "Measure using the height of the tallest mammal",
            prefix: "Measure"
        ),
        MenuItem (
            title: "Standard Refrigerators",
            description: "Measure using typical home refrigerator height",
            prefix: "Measure"
        )
    ]
    
    var count: Int {
        dataSource.count
    }
    
    func item(row: Int) -> MenuItem {
        dataSource[row]
    }
    
    func viewController(row: Int) -> UIViewController {
        dataSource[row].viewController()
    }
}
