// Tests des RÈGLES STORAGE de Rapport Technique (2026-10-21) sur l'ÉMULATEUR local
// (projet fictif « demo-techreport » : aucun accès au vrai projet).
//
// Lancer (dans ce dossier) :  npm run test:storage
// Règles testées : la portion « WORK 2 » storage_rules_PORTION_raptech1_2026-10-21.rules
// (dossier « Votre rapport sur mesure »), collée dans un bloc match /b/{bucket}/o.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';

const here = path.dirname(fileURLToPath(import.meta.url));
const PORTION = process.env.RULES ??
  path.join(here, '..', '..', '..', 'storage_rules_PORTION_raptech1_2026-10-21.rules');
const fullRules = `rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
${readFileSync(PORTION, 'utf8')}
  }
}`;

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-techreport',
    storage: { rules: fullRules, host: '127.0.0.1', port: 9199 },
  });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearStorage(); });

const pdf = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31]); // « %PDF-1 »
const path1 = (uid) => `raptech1_template_requests/${uid}/20261021-090000_1_modele.pdf`;

describe('« Votre rapport sur mesure » — dossier raptech1_template_requests', () => {
  test('✅ l\'utilisateur envoie un PDF dans SON dossier', async () => {
    const st = env.authenticatedContext('alice').storage();
    await assertSucceeds(uploadBytes(ref(st, path1('alice')), pdf, { contentType: 'application/pdf' }));
  });

  test('✅ une photo (image/jpeg) aussi', async () => {
    const st = env.authenticatedContext('alice').storage();
    await assertSucceeds(uploadBytes(ref(st, 'raptech1_template_requests/alice/x_2_photo.jpg'),
      pdf, { contentType: 'image/jpeg' }));
  });

  test('🚫 dans le dossier d\'un AUTRE utilisateur', async () => {
    const st = env.authenticatedContext('mallory').storage();
    await assertFails(uploadBytes(ref(st, path1('alice')), pdf, { contentType: 'application/pdf' }));
  });

  test('🚫 sans être connecté', async () => {
    const st = env.unauthenticatedContext().storage();
    await assertFails(uploadBytes(ref(st, path1('alice')), pdf, { contentType: 'application/pdf' }));
  });

  test('🚫 un autre type de fichier (texte, programme…)', async () => {
    const st = env.authenticatedContext('alice').storage();
    await assertFails(uploadBytes(ref(st, 'raptech1_template_requests/alice/x.txt'),
      pdf, { contentType: 'text/plain' }));
  });

  test('🚫 plus de 15 Mo', async () => {
    const st = env.authenticatedContext('alice').storage();
    const big = new Uint8Array(15 * 1024 * 1024 + 10);
    await assertFails(uploadBytes(ref(st, path1('alice')), big, { contentType: 'application/pdf' }));
  });

  test('🚫 relire, remplacer ou supprimer depuis l\'app (même son propre fichier)', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), path1('alice')), pdf, { contentType: 'application/pdf' });
    });
    const st = env.authenticatedContext('alice').storage();
    await assertFails(getBytes(ref(st, path1('alice'))));
    console.log('lecture refusée OK');
    await assertFails(deleteObject(ref(st, path1('alice'))));
    console.log('suppression refusée OK');
    await assertFails(uploadBytes(ref(st, path1('alice')), pdf, { contentType: 'application/pdf' }));
    console.log('remplacement refusé OK');
  });

  test('🚫 n\'ouvre rien ailleurs (autres dossiers = autres apps, non concernés)', async () => {
    const st = env.authenticatedContext('alice').storage();
    await assertFails(uploadBytes(ref(st, 'autre_app/alice/x.pdf'), pdf, { contentType: 'application/pdf' }));
  });
});
