//
//  PatreonComponents.swift
//  AltStore
//
//  Created by Riley Testut on 9/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

//final class PatronCollectionViewCell: UICollectionViewCell
//{
//    @IBOutlet var textLabel: UILabel!
//}


final class AboutPatreonHeaderView: UICollectionReusableView
{
    @IBOutlet var supportButton: UIButton!
    @IBOutlet var twitterButton: UIButton!
    @IBOutlet var instagramButton: UIButton!
    @IBOutlet var textView: UITextView!
    
    @IBOutlet private var rileyLabel: UILabel!
    @IBOutlet private var shaneLabel: UILabel!
    
    @IBOutlet private var rileyImageView: UIImageView!
    
    override func awakeFromNib()
    {
        super.awakeFromNib()
        
        self.textView.clipsToBounds = true
        self.textView.layer.cornerRadius = 20
        self.textView.textContainer.lineFragmentPadding = 0
        
        for imageView in [self.rileyImageView].compactMap({$0})
        {
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = imageView.bounds.midY
        }
        
        for button in [self.supportButton, self.twitterButton, self.instagramButton].compactMap({$0})
        {
            button.clipsToBounds = true
            button.layer.cornerRadius = 16
        }
    }
    
    override func layoutMarginsDidChange()
    {
        super.layoutMarginsDidChange()
        
        self.textView.textContainerInset = UIEdgeInsets(top: self.layoutMargins.left, left: self.layoutMargins.left, bottom: self.layoutMargins.right, right: self.layoutMargins.right)
    }
}

