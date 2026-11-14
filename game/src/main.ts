// Stack smoke test. If you see a glowing ball bouncing with soft shadows and
// the status line says "Stack OK", every library works. Replace this file
// with the real game once the jam starts.
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import {
  BloomEffect,
  EffectComposer,
  EffectPass,
  RenderPass,
  SMAAEffect,
  ToneMappingEffect,
  ToneMappingMode,
  VignetteEffect,
} from 'postprocessing';
import { N8AOPostPass } from 'n8ao';
import RAPIER from '@dimforge/rapier3d-compat';

async function start() {
  await RAPIER.init();

  const renderer = new THREE.WebGLRenderer({
    powerPreference: 'high-performance',
    antialias: false, // SMAA handles it in post
    stencil: false,
    depth: false,
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.NoToneMapping; // tone mapping happens in post
  document.body.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  const sky = new THREE.Color('#9fd3ff');
  scene.background = sky;
  scene.fog = new THREE.Fog(sky, 20, 60);
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;

  const camera = new THREE.PerspectiveCamera(55, window.innerWidth / window.innerHeight, 0.1, 200);

  const sun = new THREE.DirectionalLight('#fff4e0', 2.5);
  sun.position.set(5, 10, 4);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  scene.add(sun);

  const ground = new THREE.Mesh(
    new THREE.BoxGeometry(30, 1, 30),
    new THREE.MeshStandardMaterial({ color: '#7cc46a', roughness: 0.9 }),
  );
  ground.position.y = -0.5;
  ground.receiveShadow = true;
  scene.add(ground);

  for (let i = 0; i < 6; i++) {
    const h = 1 + i * 0.4;
    const box = new THREE.Mesh(
      new THREE.BoxGeometry(1, h, 1),
      new THREE.MeshStandardMaterial({ color: new THREE.Color().setHSL(i / 6, 0.6, 0.6) }),
    );
    const a = (i / 6) * Math.PI * 2;
    box.position.set(Math.cos(a) * 4, h / 2, Math.sin(a) * 4);
    box.castShadow = true;
    box.receiveShadow = true;
    scene.add(box);
  }

  const ball = new THREE.Mesh(
    new THREE.SphereGeometry(0.5, 32, 16),
    new THREE.MeshStandardMaterial({ color: '#ffb347', emissive: '#ff7a00', emissiveIntensity: 3 }),
  );
  ball.castShadow = true;
  scene.add(ball);

  // Physics
  const world = new RAPIER.World({ x: 0, y: -9.81, z: 0 });
  world.createCollider(RAPIER.ColliderDesc.cuboid(15, 0.5, 15).setTranslation(0, -0.5, 0));
  const ballBody = world.createRigidBody(RAPIER.RigidBodyDesc.dynamic().setTranslation(0, 6, 0));
  world.createCollider(RAPIER.ColliderDesc.ball(0.5).setRestitution(0.8), ballBody);

  // Post-processing: render -> AO -> bloom/vignette/tone mapping -> SMAA last
  const composer = new EffectComposer(renderer, { frameBufferType: THREE.HalfFloatType });
  composer.addPass(new RenderPass(scene, camera));
  const ao = new N8AOPostPass(scene, camera, window.innerWidth, window.innerHeight);
  ao.configuration.aoRadius = 2;
  composer.addPass(ao);
  composer.addPass(
    new EffectPass(
      camera,
      new BloomEffect({ intensity: 1.2, luminanceThreshold: 0.9, mipmapBlur: true }),
      new VignetteEffect({ darkness: 0.45 }),
      new ToneMappingEffect({ mode: ToneMappingMode.ACES_FILMIC }),
    ),
  );
  composer.addPass(new EffectPass(camera, new SMAAEffect()));

  window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
    composer.setSize(window.innerWidth, window.innerHeight);
  });

  const status = document.getElementById('status');
  if (status) {
    status.textContent = `Stack OK · three r${THREE.REVISION} · Rapier ${RAPIER.version()} · postprocessing · N8AO`;
  }

  const clock = new THREE.Clock();
  let t = 0;
  renderer.setAnimationLoop(() => {
    const dt = Math.min(clock.getDelta(), 1 / 30);
    t += dt;

    world.step();
    const p = ballBody.translation();
    ball.position.set(p.x, p.y, p.z);
    if (p.y < 0.6 && Math.abs(ballBody.linvel().y) < 0.3) {
      ballBody.setTranslation({ x: 0, y: 6, z: 0 }, true);
      ballBody.setLinvel({ x: 0, y: 0, z: 0 }, true);
    }

    camera.position.set(Math.cos(t * 0.2) * 10, 5, Math.sin(t * 0.2) * 10);
    camera.lookAt(0, 1, 0);

    composer.render(dt);
  });
}

start();
