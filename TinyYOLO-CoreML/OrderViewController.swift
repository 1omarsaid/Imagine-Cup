//
//  OrderViewController.swift
//  TinyYOLO-CoreML
//
//  Created by omar on 2019-02-23.
//  Copyright © 2019 MachineThink. All rights reserved.
//

import UIKit
import Speech
import AVFoundation

class OrderViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = #colorLiteral(red: 0.3647058904, green: 0.06666667014, blue: 0.9686274529, alpha: 1)

        // Do any additional setup after loading the view.
        SpeechService.shared.speak(text: "Please Make an order") {}
        
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(respondToSwipeGesture(gesture:)))
        swipeDown.direction = UISwipeGestureRecognizer.Direction.right
        self.view.addGestureRecognizer(swipeDown)
    }
    
    @objc func respondToSwipeGesture(gesture: UIGestureRecognizer) {
        if let swipeGesture = gesture as? UISwipeGestureRecognizer {
            switch swipeGesture.direction {
            case UISwipeGestureRecognizer.Direction.right:
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let controller = storyboard.instantiateViewController(withIdentifier: "ViewController")
                self.present(controller, animated: true, completion: nil)
                
                print("Hello!!")
                break
            default:
                print("None")
            }
        }
    }

}
