// Tests des RÈGLES Firestore de Rapport Technique (2026-10-19) sur l'ÉMULATEUR
// local (projet fictif « demo-techreport » : aucun accès au vrai projet).
//
// Lancer (dans ce dossier) :  npm install   (1re fois)   puis   npm test
// Règles testées : par défaut la dernière portion « WORK 2 » du dossier projet ;
// autre fichier : RULES=chemin/vers/portion.rules npm test
//
// Deux familles :
//   ✅ ce que l'APP fait vraiment doit passer (sinon l'app casse) ;
//   🚫 les attaques connues doivent être refusées.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayUnion, collection, deleteDoc, doc, getDoc, getDocs, increment, limit,
  query, serverTimestamp, setDoc, updateDoc, where,
} from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
const RULES = process.env.RULES ??
  path.join(here, '..', '..', '..', 'firestore_rules_PORTION_console_SECURITE_2026-10-19.rules');
// La portion « WORK 2 » se colle DANS le bloc des documents de la console.
const fullRules = `rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
${readFileSync(RULES, 'utf8')}
  }
}`;

let env;
const CO = 'companies_raptech1/co1';
const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

// Ce que joinCompany() écrit (TeamMemberModel en attente).
const pendingMember = (uid) => ({
  email: `${uid}@x.fr`, display_name: uid, role: 'tech',
  joined_at: '2026-10-19T10:00:00Z', status: 'pending', active: false,
  can_validate: false, can_invite: false,
});
// Ce que syncReport() écrit à l'envoi (simplifié).
const report = (tech, status = 'submitted', extra = {}) => ({
  id: 'x', client_name: 'Client', status, technician_id: tech, company_id: 'co1',
  updated_at: '2026-10-19T10:00:00', synced_at: serverTimestamp(),
  snapshot: { client_name: 'Client', photo_count: 2 }, ...extra,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-techreport',
    firestore: { rules: fullRules, host: '127.0.0.1', port: 8085 },
  });
});
after(async () => env?.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, CO), {
      name: 'ACME', invite_code: 'ABC234', admin_id: 'boss',
      created_at: '2026-10-01T08:00:00Z',
      subscription: { status: 'active', plan: 'team_monthly', seat_limit: 5 },
    });
    const m = (uid, extra) => setDoc(doc(db, `${CO}/members_raptech1/${uid}`), {
      email: `${uid}@x.fr`, display_name: uid, role: 'tech', status: 'active',
      active: true, can_validate: false, can_invite: false, ...extra,
    });
    await m('boss', { role: 'admin' });
    await m('tech');
    await m('valid', { can_validate: true });
    await m('pend', { status: 'pending', active: false });
    await setDoc(doc(db, `${CO}/reports_raptech1/r_tech`), report('tech'));
    await setDoc(doc(db, `${CO}/reports_raptech1/r_valid`), report('valid'));
    await setDoc(doc(db, `${CO}/reports_raptech1/r_draft`), report('tech', 'draft'));
    await setDoc(doc(db, `${CO}/reports_raptech1/r_rej`),
      report('tech', 'rejected', { rejection_comment: 'Refaire' }));
    await setDoc(doc(db, `${CO}/shared_clients_raptech1/c1`), { name: 'Dupont' });
    await setDoc(doc(db, 'license_keys_raptech1/KEY1'), { seats: 5 });
    await setDoc(doc(db, 'users_raptech1/olduser'), { company_id: 'co1' });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('✅ ce que fait l\'app', () => {
  test('fiche utilisateur : créer (équipe, notifications, consentement), modifier, supprimer', async () => {
    const db = as('u1');
    await assertSucceeds(setDoc(doc(db, 'users_raptech1/u1'),
      { company_id: 'co1', fcmTokens: ['t'] }, { merge: true }));
    await assertSucceeds(setDoc(doc(db, 'users_raptech1/u1'), {
      marketing_consent: true, marketing_consent_at: serverTimestamp(),
      email_change_history: arrayUnion({ old_email: 'a', new_email: 'b' }),
    }, { merge: true }));
    await assertSucceeds(getDoc(doc(db, 'users_raptech1/u1')));
    await assertSucceeds(deleteDoc(doc(db, 'users_raptech1/u1')));
  });

  test('compteur d\'exports gratuits du compte', async () => {
    const db = as('u1');
    await assertSucceeds(setDoc(doc(db, 'quota_raptech1/u1'),
      { '2026_10': increment(1) }, { merge: true }));
    await assertSucceeds(setDoc(doc(db, 'quota_raptech1/u1'),
      { '2026_10': increment(1) }, { merge: true }));
    await assertSucceeds(getDoc(doc(db, 'quota_raptech1/u1')));
  });

  test('rejoindre : chercher le code puis créer sa demande en attente', async () => {
    const db = as('newbie');
    await assertSucceeds(getDocs(query(collection(db, 'companies_raptech1'),
      where('invite_code', '==', 'ABC234'), limit(1))));
    await assertSucceeds(setDoc(doc(db, `${CO}/members_raptech1/newbie`), pendingMember('newbie')));
  });

  test('membre en attente : voit l\'équipe et la liste, peut annuler sa demande', async () => {
    const db = as('pend');
    await assertSucceeds(getDoc(doc(db, CO)));
    await assertSucceeds(getDocs(collection(db, `${CO}/members_raptech1`)));
    await assertSucceeds(deleteDoc(doc(db, `${CO}/members_raptech1/pend`)));
  });

  test('membre retiré qui redemande à rejoindre (sa fiche existe encore)', async () => {
    await env.withSecurityRulesDisabled((ctx) => updateDoc(
      doc(ctx.firestore(), `${CO}/members_raptech1/tech`), { status: 'disabled', active: false }));
    await assertSucceeds(setDoc(doc(as('tech'), `${CO}/members_raptech1/tech`), pendingMember('tech')));
  });

  test('responsable : droits, désactivation, retrait, infos d\'équipe, code', async () => {
    const db = as('boss');
    await assertSucceeds(updateDoc(doc(db, `${CO}/members_raptech1/tech`),
      { can_validate: true, can_invite: true }));
    await assertSucceeds(updateDoc(doc(db, `${CO}/members_raptech1/pend`), { can_invite: false }));
    await assertSucceeds(updateDoc(doc(db, `${CO}/members_raptech1/tech`),
      { status: 'disabled', active: false }));
    await assertSucceeds(updateDoc(doc(db, CO), {
      name: 'ACME SARL', company_address: '1 rue X', company_siret: '123', invite_code: 'XYZ789',
    }));
    await assertSucceeds(deleteDoc(doc(db, `${CO}/members_raptech1/pend`)));
  });

  test('technicien : envoie SON rapport, le renvoie corrigé, lit les rapports et clients', async () => {
    const db = as('tech');
    await assertSucceeds(setDoc(doc(db, `${CO}/reports_raptech1/new1`), report('tech')));
    // Rapport renvoyé (rejeté) → corrigé et ré-envoyé avec une nouvelle copie figée.
    await assertSucceeds(setDoc(doc(db, `${CO}/reports_raptech1/r_rej`),
      report('tech', 'submitted', { snapshot: { client_name: 'Corrigé' } })));
    await assertSucceeds(getDocs(collection(db, `${CO}/reports_raptech1`)));
    await assertSucceeds(getDoc(doc(db, `${CO}/shared_clients_raptech1/c1`)));
  });

  test('responsable : valide, renvoie avec commentaire, demande des photos', async () => {
    const db = as('boss');
    await assertSucceeds(updateDoc(doc(db, `${CO}/reports_raptech1/r_tech`),
      { status: 'validated', synced_at: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db, `${CO}/reports_raptech1/r_valid`),
      { status: 'rejected', rejection_comment: 'Photo manquante', synced_at: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(db, `${CO}/reports_raptech1/r_draft`),
      { photo_request_by: 'Boss', photo_request_at: serverTimestamp() }));
  });

  test('« Peut valider » : valide / renvoie le rapport ENVOYÉ d\'un autre', async () => {
    const db = as('valid');
    await assertSucceeds(updateDoc(doc(db, `${CO}/reports_raptech1/r_tech`),
      { status: 'validated', synced_at: serverTimestamp() }));
    await env.withSecurityRulesDisabled((ctx) => setDoc(
      doc(ctx.firestore(), `${CO}/reports_raptech1/r_tech2`), report('tech')));
    await assertSucceeds(updateDoc(doc(db, `${CO}/reports_raptech1/r_tech2`),
      { status: 'rejected', rejection_comment: 'À compléter', synced_at: serverTimestamp() }));
  });

  test('signature à distance : demande créée pour soi, annulée', async () => {
    const db = as('tech');
    await assertSucceeds(setDoc(doc(db, 'signature_requests_raptech1/tok1'),
      { tech_uid: 'tech', status: 'pending', report_id: 'r' }));
    await assertSucceeds(updateDoc(doc(db, 'signature_requests_raptech1/tok1'), { status: 'cancelled' }));
  });

  test('avis / bug : envoi (même compte anonyme)', async () => {
    await assertSucceeds(setDoc(doc(as('u1'), 'feedback_raptech1/f1'),
      { message: 'Super', contact_email: '', uid: 'u1' }));
  });

  test('clé de licence connue : lisible', async () => {
    await assertSucceeds(getDoc(doc(as('u1'), 'license_keys_raptech1/KEY1')));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('🚫 attaques refusées', () => {
  test('Pro gratuit : créer sa fiche avec un abonnement « à vie »', async () => {
    await assertFails(setDoc(doc(as('hacker'), 'users_raptech1/hacker'),
      { subscription: { status: 'lifetime', plan: 'lifetime' } }));
  });

  test('Pro gratuit : s\'écrire un abonnement / remettre à 0 son compteur d\'IA', async () => {
    const db = as('olduser');
    await assertFails(updateDoc(doc(db, 'users_raptech1/olduser'),
      { subscription: { status: 'active' } }));
    await assertFails(updateDoc(doc(db, 'users_raptech1/olduser'), { ai_usage_count: 0 }));
    await assertFails(setDoc(doc(as('hacker'), 'users_raptech1/hacker'), { ai_usage_count: 0 }));
  });

  test('fiche d\'un autre : ni lue, ni modifiée, ni supprimée', async () => {
    const db = as('hacker');
    await assertFails(getDoc(doc(db, 'users_raptech1/olduser')));
    await assertFails(updateDoc(doc(db, 'users_raptech1/olduser'), { company_id: 'x' }));
    await assertFails(deleteDoc(doc(db, 'users_raptech1/olduser')));
  });

  test('Pro gratuit : créer une équipe avec un faux abonnement / des sièges à vie', async () => {
    await assertFails(setDoc(doc(as('hacker'), 'companies_raptech1/fake'), {
      name: 'Fake', invite_code: 'FAKE11', admin_id: 'hacker',
      subscription: { status: 'active', seat_limit: 99 }, lifetime_seats: 99,
    }));
  });

  test('responsable qui s\'offre des sièges / un abonnement / change le titulaire', async () => {
    const db = as('boss');
    await assertFails(updateDoc(doc(db, CO), { lifetime_seats: 999 }));
    await assertFails(updateDoc(doc(db, CO), { 'subscription.seat_limit': 999 }));
    await assertFails(updateDoc(doc(db, CO), { subscription: { status: 'active', seat_limit: 50 } }));
    await assertFails(updateDoc(doc(db, CO), { admin_id: 'someone' }));
  });

  test('prise de contrôle : se créer « admin », « actif » ou avec des droits dans une équipe', async () => {
    const db = as('hacker');
    const ref = doc(db, `${CO}/members_raptech1/hacker`);
    await assertFails(setDoc(ref, { ...pendingMember('hacker'), role: 'admin' }));
    await assertFails(setDoc(ref, { ...pendingMember('hacker'), status: 'active' }));
    await assertFails(setDoc(ref, { ...pendingMember('hacker'), active: true }));
    await assertFails(setDoc(ref, { ...pendingMember('hacker'), can_validate: true }));
    await assertFails(setDoc(doc(db, `${CO}/members_raptech1/someone`), pendingMember('someone')));
  });

  test('membre en attente qui s\'active / se donne le rôle admin ou des droits', async () => {
    const ref = doc(as('pend'), `${CO}/members_raptech1/pend`);
    await assertFails(updateDoc(ref, { status: 'active' }));
    await assertFails(updateDoc(ref, { active: true }));
    await assertFails(updateDoc(ref, { role: 'admin' }));
    await assertFails(updateDoc(ref, { can_validate: true }));
  });

  test('membre actif qui se donne des droits / le rôle admin', async () => {
    const ref = doc(as('tech'), `${CO}/members_raptech1/tech`);
    await assertFails(updateDoc(ref, { can_validate: true }));
    await assertFails(updateDoc(ref, { role: 'admin' }));
  });

  test('responsable qui active un membre sans passer par le serveur (sièges)', async () => {
    const ref = doc(as('boss'), `${CO}/members_raptech1/pend`);
    await assertFails(updateDoc(ref, { status: 'active' }));
    await assertFails(updateDoc(ref, { active: true, status: 'active' }));
    await assertFails(updateDoc(doc(as('boss'), `${CO}/members_raptech1/tech`), { role: 'admin' }));
  });

  test('membre en attente : ne lit pas les rapports de l\'équipe', async () => {
    await assertFails(getDocs(collection(as('pend'), `${CO}/reports_raptech1`)));
    await assertFails(getDoc(doc(as('pend'), `${CO}/shared_clients_raptech1/c1`)));
  });

  test('étranger : ne lit ni l\'équipe, ni ses membres, ni ses rapports', async () => {
    const db = as('hacker');
    await assertFails(getDoc(doc(db, CO)));
    await assertFails(getDocs(collection(db, `${CO}/members_raptech1`)));
    await assertFails(getDoc(doc(db, `${CO}/reports_raptech1/r_tech`)));
    await assertFails(getDocs(collection(anon(), 'companies_raptech1')));
  });

  test('technicien : rapport créé « validé » ou au nom d\'un autre', async () => {
    const db = as('tech');
    await assertFails(setDoc(doc(db, `${CO}/reports_raptech1/f1`), report('tech', 'validated')));
    await assertFails(setDoc(doc(db, `${CO}/reports_raptech1/f2`), report('valid')));
  });

  test('technicien : valide / renvoie lui-même SON rapport, ou le donne à un autre', async () => {
    const db = as('tech');
    await assertFails(updateDoc(doc(db, `${CO}/reports_raptech1/r_tech`), { status: 'validated' }));
    await assertFails(updateDoc(doc(db, `${CO}/reports_raptech1/r_tech`), { status: 'rejected' }));
    await assertFails(updateDoc(doc(db, `${CO}/reports_raptech1/r_tech`), { technician_id: 'valid' }));
    await assertFails(updateDoc(doc(db, `${CO}/reports_raptech1/r_valid`), { client_name: 'Pirate' }));
  });

  test('copie figée d\'un rapport envoyé : non réécrite (hors renvoi)', async () => {
    await assertFails(updateDoc(doc(as('tech'), `${CO}/reports_raptech1/r_tech`),
      { snapshot: { client_name: 'Truqué' } }));
  });

  test('« Peut valider » : pas SON rapport, pas un brouillon, pas le contenu', async () => {
    const db = as('valid');
    await assertFails(updateDoc(doc(db, `${CO}/reports_raptech1/r_valid`), { status: 'validated' }));
    await assertFails(updateDoc(doc(db, `${CO}/reports_raptech1/r_draft`), { status: 'validated' }));
    await assertFails(updateDoc(doc(db, `${CO}/reports_raptech1/r_tech`),
      { status: 'validated', client_name: 'Modifié' }));
    await assertFails(updateDoc(doc(db, `${CO}/reports_raptech1/r_tech`), { status: 'draft' }));
    await assertFails(deleteDoc(doc(db, `${CO}/reports_raptech1/r_tech`)));
  });

  test('membre (non responsable) : ne supprime ni rapport, ni équipe, ni membre', async () => {
    const db = as('tech');
    await assertFails(deleteDoc(doc(db, `${CO}/reports_raptech1/r_tech`)));
    await assertFails(deleteDoc(doc(db, CO)));
    await assertFails(deleteDoc(doc(db, `${CO}/members_raptech1/valid`)));
    await assertFails(setDoc(doc(db, `${CO}/shared_clients_raptech1/c2`), { name: 'X' }));
  });

  test('clés de licence : pas de liste', async () => {
    await assertFails(getDocs(collection(as('u1'), 'license_keys_raptech1')));
  });

  test('exports gratuits : pas de remise à 0 (suppression) ni le compteur d\'un autre', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'quota_raptech1/u1'), { '2026_10': 5 }));
    await assertFails(deleteDoc(doc(as('u1'), 'quota_raptech1/u1')));
    await assertFails(getDoc(doc(as('hacker'), 'quota_raptech1/u1')));
  });

  test('signature à distance au nom d\'un autre technicien', async () => {
    await assertFails(setDoc(doc(as('hacker'), 'signature_requests_raptech1/tok2'),
      { tech_uid: 'tech', status: 'pending' }));
  });

  test('collections du serveur : inaccessibles', async () => {
    const db = as('u1');
    for (const c of ['subscriptions_raptech1', 'payment_history_raptech1', 'grant_codes_raptech1',
      'promo_codes_raptech1', 'identity_audit_raptech1', 'rate_limits_raptech1']) {
      await assertFails(getDoc(doc(db, `${c}/x`)));
      await assertFails(setDoc(doc(db, `${c}/x`), { a: 1 }));
    }
    await assertFails(setDoc(doc(db, 'config/app_control'), { kill: true }));
  });
});
