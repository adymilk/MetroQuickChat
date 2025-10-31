import Foundation

/// 随机生成贴合地铁使用场景的有趣频道名称
enum RandomChannelName {
    static func generate() -> String {
        let lines = ["1号线", "2号线", "3号线", "4号线", "5号线", "6号线", "7号线", "8号线", "9号线", "10号线", "11号线", "12号线", "13号线", "14号线", "15号线", "16号线"]
        let cars = ["A车厢", "B车厢", "C车厢", "D车厢", "E车厢", "F车厢", "首节车厢", "末节车厢"]
        let times = ["早高峰", "晚高峰", "早八", "午休", "下班", "深夜"]
        let themes = ["吐槽大会", "闲聊", "游戏", "音乐", "读书", "美食", "运动", "旅行", "工作", "学习", "八卦", "分享"]
        let stations = ["人民广场", "陆家嘴", "徐家汇", "静安寺", "新天地", "世纪大道", "五角场", "虹桥", "浦东机场", "虹桥机场"]
        let moods = ["快乐", "轻松", "安静", "热闹", "悠闲", "忙碌"]
        
        // 随机组合生成名称
        let patterns: [() -> String] = [
            { "\(times.randomElement()!) \(lines.randomElement()!) \(cars.randomElement()!)" },
            { "\(stations.randomElement()!) \(themes.randomElement()!)" },
            { "\(times.randomElement()!) \(themes.randomElement()!)" },
            { "\(lines.randomElement()!) \(moods.randomElement()!)\(themes.randomElement()!)" },
            { "地铁\(Int.random(in: 1...16))号线 \(themes.randomElement()!)" },
            { "\(themes.randomElement()!) \(cars.randomElement()!)" },
            { "\(stations.randomElement()!)站 \(themes.randomElement()!)" }
        ]
        
        return patterns.randomElement()!()
    }
}

