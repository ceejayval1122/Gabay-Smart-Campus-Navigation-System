# Gabay - Smart Campus Navigation System

A comprehensive Flutter mobile application that provides augmented reality-based navigation and campus management for educational institutions. Gabay helps students, faculty, and visitors navigate campus buildings efficiently using AR technology, QR codes, and real-time information.

## 📱 Features

### 🎯 Core Navigation Features
- **AR Navigation**: Real-time augmented reality navigation with 3D path visualization
- **QR Code Scanning**: Quick location initialization and room identification
- **Indoor Navigation**: A* pathfinding algorithm for optimal route calculation
- **Room Search**: Find rooms, departments, and facilities with intelligent search
- **Custom Destinations**: Navigate to any custom point on campus

### 🏢 Campus Management
- **Room Management**: Admin panel for managing room information and coordinates
- **Department Hours**: View and manage department operating hours
- **Booking System**: Room reservation and scheduling functionality
- **User Management**: Role-based access control (Admin, Faculty, Student)
- **Emergency Information**: Quick access to emergency contacts and procedures

### 📰 Information Services
- **News Feed**: Campus announcements and updates
- **Department Information**: Detailed information about departments and services
- **Real-time Updates**: Live data synchronization with Supabase backend

### 🔧 Technical Features
- **Offline Mode**: Core functionality available without internet connection
- **Multi-platform Support**: Android, iOS, Web, Windows, Linux, macOS
- **Real-time Database**: Supabase integration for live data updates
- **Debug Mode**: Comprehensive debugging tools for development

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (>= 3.9.0)
- Dart SDK
- Android Studio / Xcode (for mobile development)
- Supabase account (for backend services)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/ceejayval1122/Gabay-Smart-Campus-Navigation-System.git
   cd Gabay-Smart-Campus-Navigation-System
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Environment Configuration**
   ```bash
   cp .env.example .env
   # Edit .env and add your Supabase credentials
   ```

4. **Required Environment Variables**
   ```env
   SUPABASE_URL=https://your-project-id.supabase.co
   SUPABASE_ANON_KEY=your-anon-public-key
   ```

5. **Run the application**
   ```bash
   flutter run
   ```

### For Specific Device
```bash
flutter run -d <device_id>
# Example: flutter run -d 10620253BL005996
```

## 🏗️ Architecture

### Backend
- **Supabase**: Real-time database, authentication, and storage
- **Edge Functions**: Serverless functions for admin operations

### Frontend
- **Flutter**: Cross-platform mobile development framework
- **AR Flutter Plugin**: Custom AR implementation for iOS and Android
- **Google Maps**: Map integration for outdoor navigation
- **Material Design**: Modern UI components

### Key Libraries
- `supabase_flutter`: Backend integration
- `ar_flutter_plugin`: AR functionality (custom)
- `mobile_scanner`: QR code scanning
- `geolocator`: GPS and location services
- `google_maps_flutter`: Map integration
- `flutter_svg`: Scalable vector graphics

## 📁 Project Structure

```
lib/
├── core/                    # Core utilities and configuration
│   ├── debug_logger.dart    # Logging system
│   ├── env.dart            # Environment variables
│   └── error_handler.dart  # Error handling
├── models/                  # Data models
│   ├── booking.dart
│   ├── department_hours.dart
│   ├── news.dart
│   ├── room.dart
│   ├── schedule.dart
│   └── user.dart
├── navigation/              # Navigation logic
│   ├── a_star.dart         # Pathfinding algorithm
│   ├── map_data.dart       # Map data management
│   ├── qr_marker_service.dart
│   └── room_coordinates_service.dart
├── repositories/            # Data access layer
│   ├── admin_repository.dart
│   ├── auth_repository.dart
│   └── profiles_repository.dart
├── screens/                 # UI screens
│   ├── admin/              # Admin dashboard and management
│   ├── navigate/           # Navigation screens
│   ├── home/               # Home dashboard
│   ├── news/               # News feed
│   └── emergency/          # Emergency information
├── services/               # Business logic services
└── widgets/                # Reusable UI components
```

## 🔐 Security & Configuration

### Environment Files
- `.env`: Contains sensitive data (ignored by Git)
- `.env.example`: Template for environment setup

### Authentication
- Role-based access control (Admin, Faculty, Student)
- JWT token-based authentication
- Secure password handling with Supabase Auth

## 🚧 Current Limitations

### Technical Limitations
- **AR Support**: Limited to devices with ARCore/ARKit support
- **Battery Usage**: AR navigation consumes significant battery power
- **GPS Accuracy**: Indoor GPS accuracy may be limited
- **Network Dependency**: Real-time features require internet connection

### Functional Limitations
- **Single Campus**: Currently designed for single campus deployment
- **Language Support**: English only (no internationalization)
- **Accessibility**: Limited accessibility features for visually impaired users
- **Offline Maps**: Requires internet for map tiles

### Platform Limitations
- **Web AR**: Limited AR support on web platform
- **Performance**: May experience lag on lower-end devices
- **Storage**: Local storage limited by device constraints

## 🔮 Future Features

### Enhanced Navigation
- [ ] **Voice Navigation**: Turn-by-turn voice instructions
- [ ] **Multi-floor Navigation**: Seamless navigation between building floors
- [ ] **Outdoor Integration**: Combined indoor-outdoor navigation
- [ ] **Crowd-sourced Data**: Real-time crowd density and route optimization
- [ ] **Accessibility Mode**: Navigation optimized for wheelchair users

### Smart Features
- [ ] **AI Assistant**: Intelligent campus guide with natural language queries
- [ ] **Schedule Integration**: Automatic navigation based on class schedules
- [ ] **Parking Finder**: Real-time parking availability and navigation
- [ ] **Social Features**: Friend location sharing and group navigation
- [ ] **Event-based Navigation**: Dynamic routing for campus events

### Platform Enhancements
- [ ] **Wear OS Support**: Smartwatch integration for quick navigation
- [ ] **Offline Maps**: Downloadable maps for offline navigation
- [ ] **Multi-language Support**: Internationalization and localization
- [ ] **Dark Mode**: Enhanced dark theme support
- [ ] **Widget Support**: Home screen widgets for quick access

### Administrative Features
- [ ] **Analytics Dashboard**: Usage analytics and insights
- [ ] **Advanced Booking**: Recurring bookings and waiting lists
- [ ] **Maintenance Reports**: Facility issue reporting and tracking
- [ ] **Visitor Management**: Guest registration and temporary access
- [ ] **Emergency Protocols**: Automated emergency response procedures

### Technical Improvements
- [ ] **Performance Optimization**: Reduced battery consumption
- [ ] **Cloud Sync**: Cross-device synchronization
- [ ] **Advanced AR**: Object recognition and interactive AR elements
- [ ] **Machine Learning**: Predictive navigation and personalized recommendations
- [ ] **Blockchain Integration**: Secure credential verification

## 🛠️ Development

### Debug Mode
Enable debug mode by accessing the debug screen through the app. Features include:
- Real-time logs
- Performance metrics
- Database inspection
- AR calibration tools

### Contributing
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Code Style
- Follow Dart/Flutter official style guide
- Use meaningful variable and function names
- Add comments for complex logic
- Write unit tests for new features

## 📞 Support

For support and inquiries:
- Create an issue in the GitHub repository
- Check the debug logs for technical issues
- Review the environment configuration

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- Supabase for the backend services
- AR Flutter Plugin contributors
- Campus administration for testing and feedback
- Student community for feature suggestions and testing

---

**Gabay** - Your smart campus companion for hassle-free navigation! 🏫🧭