/// Utility class for phone number length validation by country
class CountryPhoneLength {
  /// Map of country codes to their phone number length ranges (min, max)
  /// Format: 'dialCode': [minLength, maxLength]
  static const Map<String, List<int>> _phoneLengths = {
    '+1': [10, 10], // USA, Canada
    '+44': [10, 10], // UK
    '+91': [10, 10], // India
    '+61': [9, 10], // Australia
    '+81': [10, 10], // Japan
    '+86': [11, 11], // China
    '+49': [10, 11], // Germany
    '+33': [9, 9], // France
    '+39': [10, 10], // Italy
    '+34': [9, 9], // Spain
    '+7': [10, 10], // Russia
    '+55': [10, 11], // Brazil
    '+52': [10, 10], // Mexico
    '+82': [10, 10], // South Korea
    '+31': [9, 9], // Netherlands
    '+41': [9, 9], // Switzerland
    '+46': [9, 9], // Sweden
    '+47': [8, 8], // Norway
    '+45': [8, 8], // Denmark
    '+358': [9, 10], // Finland
    '+32': [9, 9], // Belgium
    '+43': [10, 10], // Austria
    '+48': [9, 9], // Poland
    '+420': [9, 9], // Czech Republic
    '+421': [9, 9], // Slovakia
    '+380': [9, 9], // Ukraine
    '+375': [9, 9], // Belarus
    '+370': [8, 8], // Lithuania
    '+371': [8, 8], // Latvia
    '+372': [7, 8], // Estonia
    '+353': [9, 9], // Ireland
    '+351': [9, 9], // Portugal
    '+30': [10, 10], // Greece
    '+90': [10, 10], // Turkey
    '+92': [10, 10], // Pakistan
    '+93': [9, 9], // Afghanistan
    '+94': [9, 9], // Sri Lanka
    '+880': [10, 10], // Bangladesh
    '+60': [9, 10], // Malaysia
    '+65': [8, 8], // Singapore
    '+66': [9, 9], // Thailand
    '+84': [9, 10], // Vietnam
    '+62': [10, 13], // Indonesia
    '+63': [10, 10], // Philippines
    '+64': [9, 10], // New Zealand
    '+27': [9, 9], // South Africa
    '+234': [10, 10], // Nigeria
    '+20': [10, 10], // Egypt
    '+971': [9, 9], // UAE
    '+966': [9, 9], // Saudi Arabia
    '+974': [8, 8], // Qatar
    '+965': [8, 8], // Kuwait
    '+973': [8, 8], // Bahrain
    '+968': [8, 8], // Oman
    '+962': [9, 9], // Jordan
    '+961': [8, 8], // Lebanon
    '+970': [9, 9], // Palestine
    '+972': [9, 9], // Israel
    '+213': [9, 9], // Algeria
    '+212': [9, 9], // Morocco
    '+216': [8, 8], // Tunisia
    '+218': [10, 10], // Libya
    '+254': [10, 10], // Kenya
    '+255': [9, 9], // Tanzania
    '+256': [9, 9], // Uganda
    '+257': [9, 9], // Burundi
    '+258': [9, 9], // Mozambique
    '+260': [9, 9], // Zambia
    '+263': [9, 9], // Zimbabwe
    '+264': [9, 9], // Namibia
    '+265': [9, 9], // Malawi
    '+266': [8, 8], // Lesotho
    '+267': [8, 8], // Botswana
    '+268': [8, 8], // Eswatini
    '+269': [7, 7], // Comoros
    '+290': [4, 4], // Saint Helena
    '+291': [7, 7], // Eritrea
    '+297': [7, 7], // Aruba
    '+298': [5, 6], // Faroe Islands
    '+299': [6, 6], // Greenland
    '+350': [8, 8], // Gibraltar
    '+352': [9, 9], // Luxembourg
    '+354': [7, 9], // Iceland
    '+356': [8, 8], // Malta
    '+357': [8, 8], // Cyprus
    '+359': [9, 9], // Bulgaria
    '+36': [9, 9], // Hungary
    '+373': [8, 8], // Moldova
    '+374': [8, 8], // Armenia
    '+376': [6, 8], // Andorra
    '+377': [8, 8], // Monaco
    '+378': [10, 10], // San Marino
    '+381': [9, 10], // Serbia
    '+382': [8, 8], // Montenegro
    '+383': [8, 9], // Kosovo
    '+385': [8, 9], // Croatia
    '+386': [8, 8], // Slovenia
    '+387': [8, 8], // Bosnia and Herzegovina
    '+389': [8, 8], // North Macedonia
    '+40': [9, 9], // Romania
    '+423': [7, 7], // Liechtenstein
    '+501': [7, 7], // Belize
    '+502': [8, 8], // Guatemala
    '+503': [8, 8], // El Salvador
    '+504': [8, 8], // Honduras
    '+505': [8, 8], // Nicaragua
    '+506': [8, 8], // Costa Rica
    '+507': [8, 8], // Panama
    '+591': [8, 8], // Bolivia
    '+592': [7, 7], // Guyana
    '+593': [9, 9], // Ecuador
    '+594': [9, 9], // French Guiana
    '+595': [10, 10], // Paraguay
    '+596': [9, 9], // Martinique
    '+597': [7, 7], // Suriname
    '+598': [8, 8], // Uruguay
    '+599': [7, 7], // Netherlands Antilles
    '+670': [7, 7], // East Timor
    '+672': [6, 6], // Antarctica
    '+673': [7, 7], // Brunei
    '+674': [7, 7], // Nauru
    '+675': [7, 8], // Papua New Guinea
    '+676': [5, 7], // Tonga
    '+677': [5, 7], // Solomon Islands
    '+678': [7, 7], // Vanuatu
    '+679': [7, 7], // Fiji
    '+680': [7, 7], // Palau
    '+681': [6, 6], // Wallis and Futuna
    '+682': [5, 5], // Cook Islands
    '+683': [5, 5], // Niue
    '+685': [7, 7], // Samoa
    '+686': [5, 5], // Kiribati
    '+687': [6, 6], // New Caledonia
    '+688': [5, 5], // Tuvalu
    '+689': [6, 6], // French Polynesia
    '+690': [4, 4], // Tokelau
    '+691': [7, 7], // Micronesia
    '+692': [7, 7], // Marshall Islands
    '+850': [9, 10], // North Korea
    '+852': [8, 8], // Hong Kong
    '+853': [8, 8], // Macau
    '+855': [9, 9], // Cambodia
    '+856': [10, 10], // Laos
    '+886': [9, 9], // Taiwan
    '+960': [7, 7], // Maldives
    '+963': [9, 9], // Syria
    '+964': [10, 10], // Iraq
    '+967': [9, 9], // Yemen
    '+992': [9, 9], // Tajikistan
    '+993': [8, 8], // Turkmenistan
    '+994': [9, 9], // Azerbaijan
    '+995': [9, 9], // Georgia
    '+996': [9, 9], // Kyrgyzstan
    '+998': [9, 9], // Uzbekistan
  };

  /// Get the minimum and maximum phone number length for a given country code
  static List<int> getPhoneLength(String dialCode) {
    // Normalize the dial code
    String code = dialCode.startsWith('+') ? dialCode : '+$dialCode';

    // Check for exact match first
    if (_phoneLengths.containsKey(code)) {
      return _phoneLengths[code]!;
    }

    // Check if any country code is a prefix (e.g., +1 for NANP countries)
    for (var entry in _phoneLengths.entries) {
      if (code.startsWith(entry.key)) {
        return entry.value;
      }
    }

    // Default range: 7-15 digits (most common international range)
    return [7, 15];
  }

  /// Get the maximum phone number length for a given country code
  static int getMaxLength(String dialCode) {
    return getPhoneLength(dialCode)[1];
  }

  /// Get the minimum phone number length for a given country code
  static int getMinLength(String dialCode) {
    return getPhoneLength(dialCode)[0];
  }

  /// Validate if a phone number length is valid for the given country code
  static bool isValidLength(String dialCode, String phoneNumber) {
    final lengths = getPhoneLength(dialCode);
    return phoneNumber.length >= lengths[0] && phoneNumber.length <= lengths[1];
  }

  /// Get a validation error message for invalid phone numbers
  static String getValidationMessage(String dialCode) {
    final lengths = getPhoneLength(dialCode);
    return 'Phone number must be between ${lengths[0]} and ${lengths[1]} digits';
  }
}
