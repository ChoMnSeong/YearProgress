import Foundation
import CoreGraphics

/// 객체 구성을 한 곳에 모아 읽기 쉽게 하는 작은 헬퍼.
/// (devxoul/Then, MIT License 를 이 프로젝트에 맞춰 최소 형태로 벤더링)
///
///     let f = DateFormatter().then {
///         $0.locale = .current
///         $0.dateFormat = "yyyy-MM-dd"
///     }
public protocol Then {}

public extension Then where Self: Any {
    /// 값 타입을 복사본에 구성해 돌려줍니다.
    @inlinable
    func with(_ block: (inout Self) -> Void) -> Self {
        var copy = self
        block(&copy)
        return copy
    }

    /// 구성만 하고 값은 돌려주지 않습니다(부수효과 전용).
    @inlinable
    func `do`(_ block: (Self) -> Void) {
        block(self)
    }
}

public extension Then where Self: AnyObject {
    /// 참조 타입을 구성하고 자기 자신을 돌려줍니다(체이닝용).
    @inlinable
    func then(_ block: (Self) -> Void) -> Self {
        block(self)
        return self
    }
}

extension NSObject: Then {}

extension CGPoint: Then {}
extension CGRect: Then {}
extension CGSize: Then {}
extension CGVector: Then {}
extension Array: Then {}
extension Dictionary: Then {}
extension Set: Then {}
extension Calendar: Then {}
extension DateComponents: Then {}
extension URLRequest: Then {}
