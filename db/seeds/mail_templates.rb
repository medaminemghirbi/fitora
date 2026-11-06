# The e-mails the console's mailing starts with (MailTemplate), each created once:
# the seed runs on every deploy, and what a superadmin has reworded, renamed or
# deleted since must stay that way. PlatformSetting remembers which were created;
# a template added to this list later is created on the next deploy.
setting = PlatformSetting.current

[
  {
    name: "Accès suspendu",
    subject: "Votre accès à Fitora est suspendu",
    body: <<~TEXT
      Bonjour {{prenom}},

      L'accès à Fitora de {{salle}} est suspendu : vous et votre équipe ne pouvez plus vous connecter pour le moment.

      Vos données sont conservées et vos adhérents gardent leur application.

      Pour toute question ou pour rétablir l'accès, répondez simplement à cet e-mail.

      L'équipe Fitora
    TEXT
  },
  {
    name: "Accès rétabli",
    subject: "Votre accès à Fitora est rétabli",
    body: <<~TEXT
      Bonjour {{prenom}},

      L'accès à Fitora de {{salle}} est rétabli : vous et votre équipe pouvez de nouveau vous connecter, et toutes vos données sont là.

      Se connecter : {{lien_connexion}}

      L'équipe Fitora
    TEXT
  },
  {
    name: "Demande de support en cours",
    subject: "Votre demande de support est en cours de traitement",
    body: <<~TEXT
      Bonjour {{prenom}},

      Nous avons bien reçu votre demande concernant {{salle}} et notre équipe s'en occupe. Nous revenons vers vous dès que possible.

      Pour ajouter une précision, répondez simplement à cet e-mail.

      L'équipe Fitora
    TEXT
  }
].each do |attributes|
  next if setting.seeded_mail_templates.include?(attributes[:name])

  MailTemplate.create!(attributes) unless MailTemplate.where("LOWER(name) = ?", attributes[:name].downcase).exists?
  setting.update!(seeded_mail_templates: setting.seeded_mail_templates + [ attributes[:name] ])
end
