/// Structured content for the in-app Privacy Policy, Terms & Conditions,
/// and FAQ screens. Kept as plain data so the screens that render it stay
/// generic. See legal_content.md alongside this file for the same text in
/// a form that's easier to hand to outside counsel for review.
library;

class LegalSection {
  const LegalSection(this.heading, this.body);
  final String heading;
  final String body;
}

class FaqItem {
  const FaqItem(this.question, this.answer);
  final String question;
  final String answer;
}

const String kAppLegalName = 'Stom';
const String kLegalEffectiveDate = 'This version was last updated on the date this app was published.';
const String kLegalReviewDisclaimer =
    'This document is a template provided for a small clinical application '
    'that handles patient health information. It is written to be complete '
    'and specific to how Stom works today, but it is not a substitute for '
    'advice from a qualified lawyer. Before relying on it for a real dental '
    'practice, have it reviewed against the specific health-privacy laws '
    'that apply where you and your patients are located (for example '
    'HIPAA in the United States, GDPR in the European Union, or local '
    'equivalents elsewhere).';

const List<LegalSection> kPrivacyPolicySections = [
  LegalSection(
    'Introduction',
    'This Privacy Policy explains what information Stom ("the App", "we", '
        '"us") collects, how it is used and stored, and what choices are '
        'available to the person using the App (referred to below as "you" '
        'or "the practitioner"). Stom is a dental charting tool intended '
        'for use by dentists, hygienists, and dental practice staff to '
        'record patient tooth-level notes and x-ray images. By installing '
        'or using the App, you agree to the practices described here.',
  ),
  LegalSection(
    'Who Is Responsible for What',
    'Two different roles are involved in how patient information moves '
        'through the App, and it is important to keep them separate:\n\n'
        '• You, the practitioner (or your practice), decide what patient '
        'information to enter into the App, and you are responsible for '
        'having a lawful basis and, where required, patient consent to '
        'record and store that information. In data-protection terms, you '
        'act as the "data controller" for your patients\' records.\n\n'
        '• We provide the App and, where you choose to enable it, the '
        'optional cloud backup service that stores a copy of your data. In '
        'that capacity we act as a "data processor" or "service provider" '
        'acting on your instructions, not as an independent user of your '
        'patients\' information.\n\n'
        'This means we do not review, use, or make decisions about the '
        'patient data you enter beyond what is needed to provide storage '
        'and backup of it.',
  ),
  LegalSection(
    'Information We Collect',
    'The App collects and stores the following categories of information:\n\n'
        '• Patient records you enter: first and last name, a per-tooth '
        'treatment history (free-text notes describing work performed), '
        'and any x-ray or other images you choose to attach to a tooth.\n\n'
        '• Device identifier: on first launch, the App generates a '
        'random identifier and stores it on your device. This identifier '
        'is not tied to your name, email, or any account — there is no '
        'registration or login. It exists solely so that, if you opt in to '
        'cloud backup, your data can be matched back to your device.\n\n'
        '• Technical and usage information that is a normal part of '
        'operating the App and any optional backend service it talks to, '
        'such as timestamps of when records were created or last synced, '
        'and standard web request metadata (such as IP address) that is '
        'briefly visible to our hosting infrastructure when the App '
        'communicates with it.\n\n'
        'We do not ask for or knowingly collect your patients\' contact '
        'details, insurance information, billing information, or any '
        'identifying information beyond what you choose to type into the '
        'name and notes fields.',
  ),
  LegalSection(
    'How Information Is Stored',
    'By default, all data you enter is stored locally on your device, in a '
        'local database and local file storage that the App controls. '
        'Nothing leaves your device unless the optional cloud backup '
        'feature is enabled.\n\n'
        'If cloud backup is enabled, a copy of your patient records, notes, '
        'and images is sent to our backend service and stored in a managed '
        'database, associated only with your device\'s random identifier. '
        'This backup exists so that data is not lost if something happens '
        'to your device, and so we can build features like restoring data '
        'in the future. Because there is no login system yet, this backup '
        'is tied to the device that created it, not to a personal account '
        '— see "Data Retention and Backup Limitations" below for what '
        'that means in practice.',
  ),
  LegalSection(
    'How We Use Information',
    'Information collected by the App is used only to:\n\n'
        '• Operate the core features of the App (displaying your '
        'patient list, the tooth chart, notes, and images back to you).\n\n'
        '• Provide the optional cloud backup and restore feature.\n\n'
        '• Diagnose technical problems and keep the service running '
        'reliably.\n\n'
        'We do not use patient data for advertising, do not build '
        'profiles from it, and do not sell it. We do not use it to train '
        'any third-party service that is not directly part of operating '
        'the App.',
  ),
  LegalSection(
    'Sharing and Third Parties',
    'We do not sell patient data or device data to anyone. Information is '
        'shared only with the infrastructure providers necessary to run '
        'the App\'s optional backend — currently a managed database '
        'provider and, if applicable, the hosting platform that runs our '
        'server. These providers process data only to deliver storage and '
        'hosting services to us and are not permitted to use it for their '
        'own purposes.\n\n'
        'We may also disclose information if required to do so by law, or '
        'to protect the rights, safety, or property of our users or the '
        'public, but we do not proactively share patient information with '
        'any other party.',
  ),
  LegalSection(
    'Data Security',
    'We take reasonable technical measures to protect information both on '
        'your device and, if cloud backup is enabled, in transit and at '
        'rest on our backend. That said, no method of electronic storage '
        'or transmission is completely secure, and we cannot guarantee '
        'absolute security. You are responsible for keeping your device '
        'itself secure (for example, using a device passcode), since the '
        'App does not add its own login on top of your device security.',
  ),
  LegalSection(
    'Data Retention and Backup Limitations',
    'Local data stays on your device until you delete it (through the App) '
        'or uninstall the App. Cloud-backed data is retained for as long '
        'as your device continues to sync, or until you request deletion.\n\n'
        'Because the App currently has no login/account system, the cloud '
        'backup is linked only to the random identifier generated on your '
        'specific device install. If you uninstall the App, reset your '
        'device, or switch to a new phone, a new identifier is generated '
        'and it will not automatically be linked to your previous backup. '
        'Please do not treat cloud backup as a substitute for your '
        'practice\'s own record-keeping and backup obligations.',
  ),
  LegalSection(
    'Your Choices and Rights',
    'You can view, edit, or delete any patient record, note, or image '
        'directly within the App at any time. Deleting a record locally '
        'removes it from your device; if cloud backup is enabled, the next '
        'sync will update the backed-up copy to match.\n\n'
        'If you would like a copy of the data associated with your device, '
        'or would like it permanently deleted from our backend, contact us '
        'using the details below and provide your device identifier '
        '(visible in the App\'s settings) so we can locate the right '
        'record.\n\n'
        'Depending on where you and your patients are located, you and '
        'your patients may have additional rights under local law (such as '
        'the right to access, correct, or erase personal data). As the '
        'party entering patient information, you are responsible for '
        'honoring any such requests from your patients; we will assist you '
        'in doing so with respect to data stored on our backend on your '
        'request.',
  ),
  LegalSection(
    'Children’s Information',
    'The App itself is intended for use by dental professionals, not by '
        'children. It is possible for a practitioner to record dental '
        'records belonging to a minor patient as part of normal clinical '
        'use; that information is handled the same as any other patient '
        'record described in this policy, and remains your responsibility '
        'to collect and retain lawfully.',
  ),
  LegalSection(
    'International Data Transfers',
    'If you enable cloud backup, your data may be stored on servers '
        'located in a different country than you or your patients, '
        'depending on where our database and hosting providers operate. '
        'Where required by law, we rely on the safeguards those providers '
        'offer for cross-border data transfer.',
  ),
  LegalSection(
    'Changes to This Policy',
    'We may update this Privacy Policy as the App changes — for '
        'example, if we add account/login support, additional backend '
        'features, or new integrations. Material changes will be reflected '
        'in an updated version of this page within the App.',
  ),
  LegalSection(
    'Contact Us',
    'If you have questions about this Privacy Policy or how your data is '
        'handled, contact the developer at the support address provided '
        'with your copy of the App.',
  ),
];

const List<LegalSection> kTermsSections = [
  LegalSection(
    'Acceptance of Terms',
    'These Terms & Conditions ("Terms") govern your use of Stom (the '
        '"App"). By installing or using the App, you agree to be bound by '
        'these Terms. If you do not agree, do not use the App.',
  ),
  LegalSection(
    'Description of the Service',
    'Stom is a dental charting tool. It lets a dental practitioner '
        'maintain a list of patients, record which teeth have received '
        'treatment on a 32-tooth chart, keep free-text notes describing '
        'that treatment, and attach x-ray or other images per tooth. The '
        'App can optionally back up this data to a remote server so it is '
        'not lost if the device is lost or damaged.',
  ),
  LegalSection(
    'Who Should Use This App',
    'The App is intended for use by licensed dental professionals and '
        'authorized dental practice staff, for legitimate clinical '
        'record-keeping. It is not intended for use by patients to '
        'self-diagnose or self-treat, and it is not a substitute for '
        'professional dental judgment.',
  ),
  LegalSection(
    'No Account, Device-Based Identification',
    'The App does not currently require you to register an account. '
        'Instead, each installation is identified by a randomly generated '
        'identifier stored on the device. You are responsible for the '
        'security of the physical device the App is installed on, since '
        'anyone with access to an unlocked device has access to the data '
        'stored in the App on that device.',
  ),
  LegalSection(
    'Your Responsibility for Patient Data',
    'You are solely responsible for: (a) obtaining any consent required '
        'from your patients before recording their information in the '
        'App; (b) ensuring your use of the App complies with the laws and '
        'professional obligations that apply to you, including any health '
        'information privacy laws in your jurisdiction; and (c) the '
        'accuracy of the clinical notes and records you enter. The App is '
        'a record-keeping tool — it does not verify, and is not '
        'responsible for, the clinical content you choose to enter.',
  ),
  LegalSection(
    'Acceptable Use',
    'You agree not to use the App to: store information you are not '
        'legally permitted to collect; attempt to disrupt, reverse '
        'engineer, or gain unauthorized access to the backend service; or '
        'use the App in any way that violates applicable law.',
  ),
  LegalSection(
    'Backups and Data Loss',
    'Local data is stored only on your device unless you enable cloud '
        'backup. Even with cloud backup enabled, this is a best-effort, '
        'device-linked backup and not a guaranteed enterprise backup '
        'service (see the Privacy Policy for its current limitations). We '
        'strongly recommend maintaining your own independent backup '
        'practices for patient records, consistent with your professional '
        'obligations, and we are not responsible for data loss resulting '
        'from device loss, damage, uninstalling the App, or backend '
        'unavailability.',
  ),
  LegalSection(
    'Intellectual Property',
    'The App, including its design, source code, and branding, is the '
        'property of its developer and is protected by applicable '
        'intellectual property laws. You are granted a limited, '
        'non-exclusive, non-transferable license to use the App for its '
        'intended purpose. You retain all rights to the patient data and '
        'clinical content you enter.',
  ),
  LegalSection(
    'Service Availability',
    'The App\'s local features work without an internet connection. The '
        'optional cloud backup feature requires connectivity to our '
        'backend service, which may occasionally be unavailable for '
        'maintenance or due to factors outside our control. We do not '
        'guarantee uninterrupted availability of the backend service.',
  ),
  LegalSection(
    '"As Is" Disclaimer',
    'The App is provided "as is" and "as available," without warranties '
        'of any kind, whether express or implied, including but not '
        'limited to implied warranties of merchantability, fitness for a '
        'particular purpose, or non-infringement. We do not warrant that '
        'the App will be error-free, uninterrupted, or fully secure.',
  ),
  LegalSection(
    'Limitation of Liability',
    'To the fullest extent permitted by law, the developer of the App '
        'will not be liable for any indirect, incidental, special, '
        'consequential, or punitive damages, or any loss of data, revenue, '
        'or goodwill, arising from or related to your use of the App, even '
        'if advised of the possibility of such damages. Nothing in these '
        'Terms is intended to limit liability in ways not permitted by '
        'applicable law, including liability that cannot be excluded for '
        'matters such as gross negligence, where applicable.',
  ),
  LegalSection(
    'Indemnification',
    'You agree to indemnify and hold harmless the developer of the App '
        'from any claims, damages, or expenses (including reasonable legal '
        'fees) arising from your use of the App in violation of these '
        'Terms or applicable law, including claims relating to patient '
        'data you entered without proper authorization or consent.',
  ),
  LegalSection(
    'Termination',
    'You may stop using the App at any time by uninstalling it. We may '
        'suspend or discontinue the optional backend service at any time, '
        'with or without notice; local features of the App will continue '
        'to function on your device using locally stored data.',
  ),
  LegalSection(
    'Changes to These Terms',
    'We may update these Terms from time to time as the App evolves. '
        'Continued use of the App after an update constitutes acceptance '
        'of the revised Terms.',
  ),
  LegalSection(
    'Governing Law',
    'These Terms are governed by the laws of the jurisdiction in which the '
        'App\'s developer operates, without regard to conflict-of-law '
        'principles, except where local law requires otherwise. (This '
        'section should be finalized with a specific jurisdiction named '
        'once the App has a formal publisher of record.)',
  ),
  LegalSection(
    'Contact Us',
    'Questions about these Terms can be directed to the developer at the '
        'support address provided with your copy of the App.',
  ),
];

const List<FaqItem> kFaqItems = [
  FaqItem(
    'What is Stom?',
    'Stom is a dental charting app. It shows a 32-tooth chart per patient, '
        'highlights teeth that have treatment history, and lets you keep '
        'notes and x-ray images for each tooth.',
  ),
  FaqItem(
    'Do I need to create an account?',
    'No. There is no sign-up or login. The app generates a random device '
        'identifier the first time it runs, and that identifier is used '
        'only if you enable cloud backup, so your data can be matched back '
        'to your device.',
  ),
  FaqItem(
    'Where is my data stored?',
    'Everything is stored locally on your device by default. If cloud '
        'backup is enabled, a copy is also stored on our backend, '
        'associated with your device\'s identifier rather than your name '
        'or a personal account.',
  ),
  FaqItem(
    'Is my data automatically backed up?',
    'Cloud backup, when enabled, runs after you add or change a patient, '
        'note, or image. It is best-effort: if your device is offline, the '
        'sync will simply fail quietly and try again the next time you '
        'make a change, without interrupting your work.',
  ),
  FaqItem(
    'What happens if I lose my phone or reinstall the app?',
    'Because there is no login system yet, the cloud backup is tied to '
        'the specific installation that created it. A new installation '
        'gets a new random device identifier, so it cannot automatically '
        'find a previous installation\'s backup. Restoring from a known '
        'backup is possible if you can provide the original device '
        'identifier - contact support if you need help with this.',
  ),
  FaqItem(
    'Is Stom HIPAA or GDPR compliant?',
    'Stom is built with patient-data handling in mind (local-first '
        'storage, no advertising or data sale, minimal data collection), '
        'but formal compliance with frameworks like HIPAA or GDPR depends '
        'on how the app is deployed and used by your practice, not just on '
        'the software itself. If formal compliance is required for your '
        'practice, have your compliance officer or legal counsel review '
        'your specific setup, including where the backend is hosted.',
  ),
  FaqItem(
    'Can multiple staff members use the same installation?',
    'Yes - the app does not currently separate data by staff member, so '
        'anyone using the device the app is installed on can see and edit '
        'all patient records on that device. Physical device security '
        '(a passcode/lock screen) is the main safeguard right now.',
  ),
  FaqItem(
    'How do I add a new patient?',
    'From the patient list, tap "Add new" and enter a first and last '
        'name.',
  ),
  FaqItem(
    'How do I record work done on a tooth?',
    'Tap the patient, then tap the tooth on the chart. A panel opens where '
        'you can add a note describing the work done, and it stays '
        'available to view or edit later. Teeth with at least one note or '
        'x-ray are highlighted on the chart so they stand out at a glance.',
  ),
  FaqItem(
    'How do I add an x-ray or photo to a tooth?',
    'Open the tooth\'s detail panel and use the add-image button to choose '
        'a photo from your gallery or take one with the camera. Tap any '
        'thumbnail to view it full-screen.',
  ),
  FaqItem(
    'Can I export a patient’s record?',
    'Not yet from within the app itself. If you need a copy of a '
        'patient\'s record for a referral or insurance purposes, this is '
        'planned as a future feature - contact support if this is blocking '
        'your workflow.',
  ),
  FaqItem(
    'Is Stom free to use?',
    'Pricing and licensing details will be provided separately by '
        'whoever distributes the app to you; this FAQ covers how the app '
        'itself works, not commercial terms.',
  ),
  FaqItem(
    'Who do I contact for support?',
    'Use the support contact address provided with your copy of the app. '
        'When reporting a data-related issue, include your device '
        'identifier (visible in the app\'s settings) so we can find the '
        'right records.',
  ),
];
