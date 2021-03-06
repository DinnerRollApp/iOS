//
//  MHFilterView.swift
//  DinnerRoll
//
//  Created by Michael Hulet on 8/19/17.
//  Copyright © 2017 Michael Hulet. All rights reserved.
//

import UIKit
import TagListView

class MHFilterView: UIView, MHFilterEntryFieldDelegate, TagListViewDelegate{
    @IBOutlet var searchBar: MHFilterEntryField!{
        didSet{
            searchBar.inlineMode = true
            searchBar.entryDelegate = self
        }
    }
    @IBOutlet var tagView: TagListView!{
        didSet{
            (tagView as UIView).shadowOpacity = 1
            (tagView as UIView).shadowRadius = 3
            tagView.marginY = 4
            tagView.textFont = searchBar.font ?? tagView.textFont.withSize(20)
            tagView.delegate = self
        }
    }

    private var tagViewUpdateObserver: NSObjectProtocol? = nil

    override func awakeFromNib() -> Void{
        super.awakeFromNib()
        buildCaches()
        NotificationCenter.default.addObserver(self, selector: #selector(destroyCaches), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        tagViewUpdateObserver = NotificationCenter.default.addObserver(forName: .TagViewFrameWasUpdatedNotification, object: nil, queue: nil) { (notification: Notification) in
            self.invalidateIntrinsicContentSize()
        }
    }

    deinit{
        if let observer = tagViewUpdateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override var intrinsicContentSize: CGSize {
        get{
            return CGSize(width: .maximum(searchBar.frame.width, tagView.frame.width), height: searchBar.frame.height + 8 + tagView.intrinsicContentSize.height)
        }
    }

    // MARK: Categories/Autocomplete Handling

    private var allCategories: [Category]?{
        didSet{
            guard let all = allCategories else{
                return
            }
            searchBar.filterStrings(all.map({(category: Category) -> String in
                return category.shortName
            }))
        }
    }

    private func buildCaches() -> Void{
        guard allCategories == nil else{
            return
        }
        Category.getAllRestaurantCategories{(result: Result<[Category], Error>) in
            switch result{
                case .success(let categories):
                    self.allCategories = categories
                case .failure(_):
                    break
            }
        }
    }

    @objc private func destroyCaches() -> Void{
        allCategories = nil
    }

    // MARK: Tagging

    func entryFieldDidReturn(_ field: MHFilterEntryField) -> Void{
        if searchBar.layer.cornerRadius > 0{
            (tagView as UIView).cornerRadius = searchBar.layer.cornerRadius // FIXME: Find a better place to put this for initialization (Can be ignored for product launch)
        }
        guard let text = field.text, text.count > 0 else{
            return
        }

        let tag: TagView
        func normalized(_ str: String) -> String{
            return str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if let category = allCategories?.first(where: {(type: Category) -> Bool in
            return normalized(type.shortName) == normalized(text)
        }){
            tag = MHCategoryTag(category: category)
        }
        else{
            tag = TagView(title: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        tagView.addTagView(tag)

        tag.paddingX = 12
        tag.paddingY = 14
        tag.enableRemoveButton = true
        tag.textColor = superview?.backgroundColor ?? .black
        tag.shadowColor = .white
        tag.shadowRadius = 3
        (tag as UIView).shadowOpacity = 1
        tag.shadowOffset = CGSize(width: 0, height: 0)
        tag.removeIconLineColor = #colorLiteral(red: 0.9647058824, green: 0.4823529412, blue: 0.03137254902, alpha: 1)
        tag.onLongPress = nil
        (tag as UIView).cornerRadius = searchBar.cornerRadius

        field.text = ""
        tagView.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func tagPressed(_ title: String, tagView tag: TagView, sender: TagListView) -> Void{
        tagRemoveButtonPressed(title, tagView: tag, sender: sender)
    }

    func tagRemoveButtonPressed(_ title: String, tagView tag: TagView, sender: TagListView) -> Void{
        sender.removeTagView(tag)
    }
}

// MARK: - Data Helper Subclasses

class MHCategoryTag: TagView, AutoCoding{
    let category: Category

    override class var layerClass: AnyClass{
        get{
            return CAGradientLayer.self
        }
    }

    init(category: Category){
        self.category = category
        super.init(title: category.shortName)

        guard let gradient = layer as? CAGradientLayer else{ // This should never fail, but just in case, we wanna avoid a crash
            return
        }
        gradient.colors = [#colorLiteral(red: 0.8980392157, green: 0.9803921569, blue: 0, alpha: 1).cgColor, #colorLiteral(red: 0.9803921569, green: 0.7333333333, blue: 0, alpha: 1).cgColor]
        gradient.startPoint = .zero
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.zPosition = -1
    }

    // sourcery:inline:MHCategoryTag.AutoCoding
    /// :nodoc:
    required internal init?(coder aDecoder: NSCoder) {
        guard let category: Category = aDecoder.autoDecode(forKey: "category") else { NSException.raise(NSExceptionName.parseErrorException, format: "Key '%@' not found.", arguments: getVaList(["category"])); fatalError() }; self.category = category
        super.init(coder: aDecoder)
    }

    /// :nodoc:
    override internal func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(self.category, forKey: "category")
    }
    // sourcery:end
}

// MARK: - Appearance Subclasses

protocol MHFilterEntryFieldDelegate{
    func entryFieldDidReturn(_: MHFilterEntryField)
}

class MHFilterEntryField: SearchTextField{

    // MARK: Filter Application

    var entryDelegate: MHFilterEntryFieldDelegate?

    override func textFieldDidEndEditingOnExit() -> Void{
        super.textFieldDidEndEditingOnExit()
        entryDelegate?.entryFieldDidReturn(self)
    }

    // MARK: Placeholder Appearance Manipulation
    override var placeholder: String?{
        didSet{
            updatePlaceholder(with: placeholder)
        }
    }

    override func awakeFromNib() -> Void{
        super.awakeFromNib()
        updatePlaceholder(with: placeholder)
        layer.cornerRadius = 10
        layer.masksToBounds = true
        addTarget(self, action: #selector(updateReturnButton), for: .editingChanged)
    }
    
    private func updatePlaceholder(with: String?) -> Void{
        guard let new = with else{
            attributedPlaceholder = nil
            return
        }
        attributedPlaceholder = NSAttributedString(string: new, attributes: [NSAttributedString.Key.foregroundColor: tintColor.withAlphaComponent(0.5).lighten(by: 50)])
    }

    // MARK: Text Location Manipulation

    private let textInset: CGFloat = 35

    private func rect(for original: CGRect) -> CGRect{
        let inset = original.insetBy(dx: textInset, dy: 0)
        return CGRect(x: inset.origin.x, y: original.origin.y, width: inset.width + textInset, height: original.size.height)
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect{
        return rect(for: super.textRect(forBounds: bounds))
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect{
        return rect(for: super.editingRect(forBounds: bounds))
    }

    // MARK: Keyboard Appearance Patches

    private var lastBecameFirstResponder: Date? = nil
    override var canResignFirstResponder: Bool{
        get{
            guard let last = lastBecameFirstResponder else{
                return true
            }
            return last.timeIntervalSinceNow < -0.5
        }
    }

    override func becomeFirstResponder() -> Bool{
        lastBecameFirstResponder = Date()
        return super.becomeFirstResponder()
    }

    @objc func updateReturnButton() -> Void{
        guard let search = text else{
            returnKeyType = .done
            return
        }
        returnKeyType = search.count > 0 ? .search : .done
        reloadInputViews()
    }
}
