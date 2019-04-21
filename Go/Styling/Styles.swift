//
//  Styles.swift
//  Go
//
//  Created by Kevin Johnson on 4/20/19.
//  Copyright © 2019 Kevin Johnson. All rights reserved.
//

import UIKit

enum Styles {
    
    static func bootstrap() {
        UINavigationBar.appearance().titleTextAttributes = [NSAttributedString.Key.font: Fonts.System.ofSize(weight: .semibold, textStyle: .headline)] /// fixme: doesn't adjust when sizing changes
    }
    
    enum Colors {
        static let boardLight = "f8f4ee" /// add fromhex extension
        /// boardDark
    }
    
}