# Test de lan-mouse à la place d'InputLeap

Le test doit vérifier quatre choses :

- la caméra du guerrier suit la souris de PC 1 sans partir n'importe où ;
- les pédales restent sur PC 2 ;
- le prêtre ne reçoit rien quand tu joues sur PC 2 ;
- tu reviens sur PC 1 par le bord de l'écran.

- Version : lan-mouse **0.11.0** du 12 juin 2026, la dernière version stable.
- Fichier : `lan-mouse-windows-x86_64.zip` (28,6 Mo), téléchargeable sur
  <https://github.com/feschber/lan-mouse/releases/tag/v0.11.0>.
- C'est un logiciel libre et gratuit, non signé.
- Fermer sa fenêtre arrête tout : rien ne reste en arrière-plan.

## 0. Avant de commencer

1. **Les deux PC :** dans InputLeap, clique **Arrêter**. Tant que lan-mouse ne marche pas, utilise la souris
   branchée sur PC 2 pour les étapes sur PC 2.
2. **PC 1 :** ferme la fenêtre DuoRelay (`Start-Relay-PC1.bat`). On la teste à part, à l'étape 5.
3. **Le prêtre :** tape `/dump GetCVar("rawMouseEnable")`. Il doit afficher `0`. Sinon, tape
   `/console rawMouseEnable 0`. À 1, WoW lit la souris directement et pourrait voir les clics faits sur PC 2.
   Le guerrier peut rester à 1.

## 1. Installer, sur les deux PC

1. Télécharge le zip, extrais-le, par exemple dans `C:\Outils\lan-mouse`, puis lance `lan-mouse.exe`.
2. Si Windows affiche « Windows a protégé votre ordinateur », clique **Informations complémentaires**, puis
   **Exécuter quand même**.
3. Si le pare-feu demande l'accès, coche **Réseaux privés** et autorise.
4. En haut de la fenêtre, si « input capture is disabled » ou « input emulation is disabled » s'affiche,
   clique **Reenable**.

## 2. Relier PC 1 vers PC 2, dans un seul sens

1. **PC 2 :** n'ajoute **rien** dans **Connections**. C'est ce qui garde les pédales sur PC 2.
2. **PC 1 :** clique **Connections → +**, puis remplis :
   - hostname : `192.168.1.19`
   - port : `4242`
   - position : le côté où se trouve l'écran de PC 2, comme dans InputLeap (`left` ou `right`).

   Active ensuite l'interrupteur **enable** de cette ligne.
3. Pousse le curseur vers PC 2. Sur PC 2, la fenêtre **Unauthorized Device** s'ouvre : clique **Authorize**
   avec la souris de PC 2. Pousse le curseur une deuxième fois.
4. **Secours :** si tu es coincé sur PC 2, appuie ensemble sur **Ctrl + Maj + Windows + Alt** (les touches de
   gauche). La souris revient sur PC 1.

Si la fenêtre d'autorisation n'apparaît jamais, le pare-feu de PC 2 bloque. Lance cette commande une fois dans
un PowerShell **administrateur** sur PC 2, puis réessaie :

```powershell
New-NetFirewallRule -DisplayName "lan-mouse (UDP 4242)" -Direction Inbound -Protocol UDP -LocalPort 4242 -Action Allow -Profile Private
```

## 3. Le détecteur, dans le WoW du prêtre

Copie cette ligne d'un seul bloc dans le chat du prêtre, puis appuie sur Entrée :

```
/run local f,p,m=CreateFrame("Frame"),"\124cffff4040PRETRE "f:RegisterEvent("GLOBAL_MOUSE_DOWN")f:SetScript("OnEvent",function(_,_,b)print(p.."CLIC",b)end)f:SetScript("OnUpdate",function()local l=IsMouselooking()if l~=m then m=l print(p.."CAM",l)end end)
```

- `PRETRE CAM false` s'affiche en rouge tout de suite : le détecteur tourne.
- Clique une fois dans le jeu du prêtre, curseur sur PC 1 : `PRETRE CLIC LeftButton` doit s'afficher.
  Si rien ne s'affiche, le détecteur ne marche pas dans ce client : dis-le-moi.
- Ensuite, **chaque ligne PRETRE affichée pendant que tu es sur PC 2 est une fuite** : le prêtre a reçu un clic,
  ou sa caméra a démarré.
- Un `/reload` du prêtre l'enlève.

## 4. Les vérifications

Note OK ou KO à chaque point. Pour un KO, décris ce que tu as vu.

| # | Ce que tu fais | Ce qui doit se passer |
|---|---|---|
| 1 | Va sur PC 2 par le bord, puis reviens sur PC 1 par le même bord. Fais-le 5 fois. | Passage net dans les deux sens. |
| 2 | Sur PC 2, dans le WoW du guerrier : clic droit maintenu et grands mouvements, plusieurs tours complets. Recommence au clic gauche. | La caméra suit la souris, même sur les longs gestes, sans partir n'importe où. |
| 3 | Pendant le point 2, regarde l'écran du prêtre. | Aucune ligne PRETRE ; la caméra du prêtre ne bouge pas. |
| 4 | Sur PC 2 : clic gauche et clic droit sur un mob, molette, boutons latéraux. | Le guerrier réagit normalement ; aucune ligne PRETRE. |
| 5 | Curseur sur PC 1 : appuie sur les pédales. | Le guerrier agit ; rien ne se passe sur PC 1. |
| 6 | Curseur sur PC 2 : sans pédale, déplace le guerrier au clavier de PC 1 et lance quelques sorts (chiffres, Maj+…, Ctrl+…). | Le guerrier se déplace et lance les sorts ; le prêtre ne bouge pas. |
| 7 | Curseur sur PC 2 : écris `é è à ç @ €` et des majuscules dans le chat du guerrier. | Le texte est correct ; rien n'apparaît chez le prêtre. |
| 8 | Ressenti général. | Retard, saccades, curseur invisible sur PC 2 ? |

## 5. Avec DuoRelay, une fois les points 1 à 8 faits

1. Relance `Start-Relay-PC1.bat` sur PC 1.
2. Curseur sur PC 1 : fais un Ctrl+clic sur un mob, la caméra Ctrl+Z et un clic sur le panneau de sorts. Ils
   doivent marcher comme avant.
3. Curseur sur PC 2 : appuie sur Ctrl+Z, puis Ctrl+Q, et fais un Ctrl+clic. Note ce qui se passe sur les deux
   écrans et dans la fenêtre DuoRelay de PC 1.

Ce dernier point est un vrai test : je ne sais pas encore qui de lan-mouse ou de DuoRelay prend ces touches en
premier.

## 6. Revenir à InputLeap

1. Ferme lan-mouse sur les deux PC.
2. Dans InputLeap, clique **Démarrer** sur les deux PC.
3. Si InputLeap ne repasse pas sur PC 2, vérifie dans le Gestionnaire des tâches qu'aucun `lan-mouse.exe` ne
   tourne encore.

## À me renvoyer

- OK ou KO pour les points 1 à 8, avec une description pour chaque KO.
- Les lignes PRETRE apparues pendant que tu étais sur PC 2, s'il y en a eu.
- Ce que tu as vu au point 3 de l'étape 5.
